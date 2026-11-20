"""Extract and validate the UNI Clicker timing snapshots."""

import json
from pathlib import Path
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
    expected = f"Hello, UNI Clicker from {language}!\r\n".encode()
    require((directory / "uart.txt").read_bytes() == expected * 2, "USART6 greeting changed")
    (directory / "trace.bin").write_bytes(trace)


def timeline(events, category):
    for frame in events:
        if record := frame.get(category):
            for name, fields in record["kind"].items():
                yield name, record["ts"], fields


def verify(directory, mode):
    events = [json.loads(line) for line in (directory / "events.jsonl").read_text().splitlines()]
    resolutions = [
        event["BaseMetadata"]["TsResolutionNs"]["ns_per_ts"]
        for event in events if "TsResolutionNs" in event.get("BaseMetadata", {})
    ]
    require(resolutions == [1_000_000], f"unexpected timestamp units {resolutions}")
    base = list(timeline(events, "Base"))
    require(all(fields["cnt"] == 0 for name, _, fields in base if name == "DroppedEvtCnt"),
            "trace reports dropped events")
    heartbeats = [(ts, fields["val"]) for kind, ts, fields in base
                  if kind == "Valmarker" and fields["valmarker_id"] == 0]
    require([value for _, value in heartbeats] == [1, 2], f"unexpected heartbeat trace {heartbeats}")
    if mode == "bare-metal":
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
    {"extract": extract, "verify": verify}[action](Path(output), parameter)
