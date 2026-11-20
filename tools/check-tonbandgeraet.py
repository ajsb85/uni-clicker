"""Extract and validate the UNI Clicker timing snapshots."""

import csv
import json
from pathlib import Path
from statistics import median
import struct
import sys


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def extract(directory, language):
    snapshot = (directory / "sram.bin").read_bytes()
    require(len(snapshot) >= 4, "truncated snapshot header")
    length, = struct.unpack_from("<I", snapshot)
    require(0 < length <= len(snapshot) - 4, f"invalid snapshot byte count {length}")
    trace = snapshot[4:4 + length]
    require(trace[-1] == 0, "snapshot ends inside a trace frame")
    if language:
        expected = f"Hello, UNI Clicker from {language}!\r\n".encode()
        require((directory / "uart.txt").read_bytes() == expected * 2, "USART6 greeting changed")
    (directory / "trace.bin").write_bytes(trace)


def timeline(events, category):
    for frame in events:
        if record := frame.get(category):
            for name, fields in record["kind"].items():
                yield name, record["ts"], fields


def verify_console(directory, base, events, profile):
    strict = profile == "freertos-console"
    rtos = list(timeline(events, "FreeRTOS"))
    metadata = [frame["FreeRTOSMetadata"] for frame in events if "FreeRTOSMetadata" in frame]
    queues = {item["QueueName"]["queue_id"] for item in metadata
              if "QueueName" in item and item["QueueName"]["name"] == "USART6 RX"}
    require(len(queues) == 1, f"expected one USART6 RX queue, got {queues}")
    queue, = queues
    send = "QueueSendFromIsr"
    receive = "QueueReceive"
    transactions = [(kind, fields["len_after"]) for kind, _, fields in rtos
                    if kind in (send, receive) and fields["queue_id"] == queue]
    normal = [(send, 1), (receive, 0)]
    burst = [(send, depth) for depth in range(1, 5)] + [(receive, depth) for depth in range(3, -1, -1)]
    markers = [[(fields["val"], ts) for kind, ts, fields in base
                if kind == "Valmarker" and fields["valmarker_id"] == marker] for marker in (0, 1)]
    sent, received = ([index for index, _ in pairs] for pairs in markers)
    expected = [*range(1, 14), 20, 21, 22]
    if not strict:
        status = json.loads((directory / "console.json").read_text())
        burst_sequences = [index for index in sent if 10 <= index <= 19]
        require(burst_sequences == sorted(set(burst_sequences))
                and len(burst_sequences) == status["burst_replies"],
                "UART replies disagree with the burst trace")
        expected = [*range(1, 10), *burst_sequences, 20, 21, 22]
        depth = 0
        for kind, size in transactions:
            depth += 1 if kind == send else -1
            require(size == depth and 0 <= depth <= 4, f"unexpected queue depth {size}")
        require(depth == 0 and len(transactions) == 2 * len(expected),
                "UART queue trace is incomplete")
    else:
        require(transactions == normal * 9 + burst + normal * 3, f"unexpected queue events {transactions}")
    require(sent == received == expected,
            "USART6 enqueue and dequeue sequences differ")
    rows = ["sequence\tenqueue_us\tdequeue_us\tlatency_us\tworkload"]
    maximum = 0
    for (index, enqueued), (_, dequeued) in zip(*markers):
        latency = dequeued - enqueued
        workload = "burst" if 10 <= index <= 19 else "isolated"
        budget = 1500 if workload == "burst" else 500
        require(0 < latency <= budget if strict else latency >= 0,
                f"unexpected command {index} latency {latency} us")
        rows.append(f"{index}\t{enqueued}\t{dequeued}\t{latency}\t{workload}")
        maximum = max(maximum, latency)
    (directory / "latency.tsv").write_text("\n".join(rows) + "\n")
    environment = "on the board" if profile.endswith("-hardware") else "in Renode"
    print(f"Verified {len(expected)} IRQ-to-task deliveries {environment}. Maximum latency {maximum} us.")


def baseline(directory, repeat):
    buckets = {"isolated": [], "burst": []}
    runs = []
    for i in range(1, int(repeat) + 1):
        run = directory / f"run-{i}"
        runs.append(json.loads((run / "console.json").read_text()))
        with (run / "latency.tsv").open() as values:
            for row in csv.DictReader(values, delimiter="\t"):
                buckets[row["workload"]].append(int(row["latency_us"]))
    summary = {name: {"samples": len(values), "min_us": min(values), "median_us": median(values),
                      "max_us": max(values)} for name, values in buckets.items()}
    (directory / "baseline.json").write_text(json.dumps({"runs": runs, **summary}, indent=2) + "\n")


def verify(directory, profile):
    events = [json.loads(line) for line in (directory / "events.jsonl").read_text().splitlines()]
    resolutions = [
        event["BaseMetadata"]["TsResolutionNs"]["ns_per_ts"]
        for event in events if "TsResolutionNs" in event.get("BaseMetadata", {})
    ]
    console = profile.startswith("freertos-console")
    require(resolutions == [1_000 if console else 1_000_000], f"unexpected timestamp units {resolutions}")
    base = list(timeline(events, "Base"))
    require(all(fields["cnt"] == 0 for name, _, fields in base if name == "DroppedEvtCnt"),
            "trace reports dropped events")
    if console:
        return verify_console(directory, base, events, profile)
    heartbeats = [(ts, fields["val"]) for kind, ts, fields in base
                  if kind == "Valmarker" and fields["valmarker_id"] == 0]
    require([value for _, value in heartbeats] == [1, 2], f"unexpected heartbeat trace {heartbeats}")
    if profile == "stm32cube":
        intervals = [(kind, ts) for kind, ts, fields in base
                     if kind in ("EvtmarkerBegin", "EvtmarkerEnd") and fields["evtmarker_id"] == 0]
        require([kind for kind, _ in intervals] == ["EvtmarkerBegin", "EvtmarkerEnd"] * 2,
                f"unexpected delay markers {intervals}")
        delays = [intervals[i + 1][1] - intervals[i][1] for i in (0, 2)]
        require(delays == [501, 501], f"expected two 501 ms HAL waits, got {delays}")
        require([ts for ts, _ in heartbeats] == [intervals[i][1] for i in (1, 3)],
                "heartbeat did not follow the delay markers")
        print("Two 501 ms HAL waits and both PD7 heartbeat markers verified.")
    else:
        rtos = list(timeline(events, "FreeRTOS"))
        metadata = [frame["FreeRTOSMetadata"] for frame in events if "FreeRTOSMetadata" in frame]
        queues = {item["QueueName"]["queue_id"] for item in metadata
                  if "QueueName" in item and item["QueueName"]["name"] == "Heartbeat"}
        require(len(queues) == 1, f"expected one Heartbeat queue, got {queues}")
        queue, = queues
        transactions = [(kind, ts, fields["len_after"]) for kind, ts, fields in rtos
                        if kind in ("QueueSend", "QueueReceive") and fields["queue_id"] == queue]
        require([(kind, size) for kind, _, size in transactions]
                == [("QueueSend", 1), ("QueueReceive", 0)] * 2,
                f"unexpected queue events {transactions}")
        sends = [transactions[i][1] for i in (0, 2)]
        receives = [transactions[i][1] for i in (1, 3)]
        require(sends[1] - sends[0] == 500, f"unexpected queue period {sends}")
        require([ts for ts, _ in heartbeats] == receives
                and all(0 <= rx - tx <= 1 for tx, rx in zip(sends, receives)),
                f"unexpected queue delivery latency {transactions}")
        switched = {fields["task_id"] for kind, _, fields in rtos if kind == "TaskSwitchedIn"}
        task_names = {item["TaskName"]["name"] for item in metadata
                      if "TaskName" in item and item["TaskName"]["task_id"] in switched}
        require({"hello", "receiver"} <= task_names, f"missing task switches {task_names}")
        print("FreeRTOS task switches and two queue deliveries at 500 ms spacing verified.")


if __name__ == "__main__":
    action, output, parameter = sys.argv[1:]
    {"extract": extract, "verify": verify, "baseline": baseline}[action](Path(output), parameter)
