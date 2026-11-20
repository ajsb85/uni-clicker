#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/bench-env.sh
if [[ $# -gt 1 || ( $# == 1 && "$1" != --hardware ) ]]; then
    echo 'Usage: tools/check-systemview.sh [--hardware]' >&2
    exit 2
fi

mkdir -p .cache/verification
out=$(mktemp -d "$PWD/.cache/verification/systemview.XXXXXX")
printf 'SystemView artifacts %s\n' "$out"
make systemview-elf systemview-cli SYSTEMVIEW_BUILD_DIR="$out" >"$out/build.log" 2>&1 || {
    cat "$out/build.log" >&2
    exit 1
}
cli=build/systemview-cli/debug/systemview-cli
elf="$out/hello.elf"
{
    printf 'kind\tname\tvalue\n'
    printf 'source\tcommit\t%s\n' "$(git rev-parse HEAD)"
    printf 'source\tsystemview\t%s\n' "$(git -C "$SEGGER_SYSTEMVIEW_ROOT" rev-parse HEAD)"
    printf 'source\trtt\t%s\n' "$(git -C "$SEGGER_RTT_ROOT" rev-parse HEAD)"
    printf 'elf_sha256\tfirmware\t%s\n' "$(sha256sum <"$elf" | cut -d' ' -f1)"
    printf 'tool\trenode\t%s\n' "$("$RENODE" --version | sed -n '1p')"
    printf 'tool\tarm-none-eabi-gcc\t%s\n' "$("${STM32_GCC:-arm-none-eabi-gcc}" --version | sed -n '1p')"
} >"$out/provenance.tsv"

verify() {
    local recording=$1 transport=$2
    "$cli" decode "$recording/trace.bin" >"$recording/events.jsonl"
    "$cli" summary "$recording/trace.bin" >"$recording/summary.json"
    python3 - "$recording" "$transport" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
mode = sys.argv[2]
events = [json.loads(line) for line in (path / "events.jsonl").read_text().splitlines()]
core, = json.loads((path / "summary.json").read_text())["cores"]
names = [event["event"] for event in events]
if (core["reported_dropped"] or core["timestamp_hz"] != 1000 or core["cpu_hz"] != 16000000
        or core["system"].get("N") != "UNI Clicker"
        or names.count("trace_start") != 1 or names[0] != "trace_start"
        or names.count("trace_stop") != 1 or names[-1] != "trace_stop"
        or "undecoded" in names):
    raise SystemExit(f"Unexpected SystemView recording. See {path}.")
markers = [item["ticks"] for item in events if item["event"] == "mark" and
           item["data"]["name"] == "PD7 heartbeat"]
if not (len(markers) == 3 if mode == "Renode" else 5 <= len(markers) <= 9):
    raise SystemExit(f"Unexpected heartbeat count {len(markers)}. See {path}.")
if any(second - first != 250 for first, second in zip(markers, markers[1:])):
    raise SystemExit(f"Unexpected heartbeat spacing {markers}.")
print(f"{mode}: {len(events)} events, {len(markers)} PD7 markers at 250 ms spacing, zero dropped events.")
PY
}

mkdir "$out/renode"
python3 tools/simulate-systemview.py "$elf" "$out/renode"
verify "$out/renode" Renode
if [[ ${1:-} != --hardware ]]; then
    exit 0
fi

exec 9>.cache/probe.lock
flock -n 9 || { echo 'Another bench run owns the probe.' >&2; exit 1; }
physical="$out/hardware"
mkdir "$physical"
port=9090
server=
cleanup() {
    if [[ -n "$server" ]]; then
        kill "$server" 2>/dev/null || true
        wait "$server" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

read -r cb cb_size < <(arm-none-eabi-nm -S "$elf" | awk '$4 == "_SEGGER_RTT" {print "0x" $1, "0x" $2}')
read -r terminal terminal_size < <(arm-none-eabi-nm -S "$elf" | awk '$4 == "_acUpBuffer" {print "0x" $1, "0x" $2}')
terminal_file="$physical/terminal.bin"
if [[ "$OPENOCD" == *.exe ]]; then
    elf=$(wslpath -m "$elf")
    terminal_file=$(wslpath -m "$terminal_file")
fi
# Use Tcl braces for Windows paths and the RTT signature, which contains a space.
debug/start-openocd.sh \
    -c 'reset halt' \
    -c 'if {([lindex [read_memory 0xe0042000 32 1] 0] & 0xfff) != 0x449 || [lindex [read_memory 0x1ff0f442 16 1] 0] != 1024} {error "Expected STM32F746ZG with 1 MiB flash"}' \
    -c "program {$elf} verify reset" \
    -c "sleep 250; halt; dump_image {$terminal_file} $terminal $terminal_size; resume" \
    -c "rtt setup $cb $cb_size {SEGGER RTT}; rtt start; rtt server start $port 1" \
    >"$physical/openocd.log" 2>&1 &
server=$!
for ((attempt=0; attempt<150; ++attempt)); do
    kill -0 "$server" 2>/dev/null || break
    if grep -iq "Listening on port $port for rtt" "$physical/openocd.log"; then
        break
    fi
    sleep 0.1
done
grep -iq "Listening on port $port for rtt" "$physical/openocd.log" || {
    cat "$physical/openocd.log" >&2
    exit 1
}
grep -Fq 'Verified OK' "$physical/openocd.log"
timeout --kill-after=2s 12s "$cli" capture "127.0.0.1:$port" --transport rtt --seconds 2 >"$physical/trace.bin"
terminal_banner='UNI Clicker RTT ready'
head -c "$((${#terminal_banner} + 1))" "$physical/terminal.bin" >"$physical/terminal.txt"
cmp "$physical/terminal.txt" <(printf '%s\n' "$terminal_banner")
verify "$physical" 'ST-LINK RTT'
timeout --kill-after=2s 10s "${GDB:-gdb-multiarch}" -nx -q -batch \
    -ex 'set remotetimeout 2' -ex "target extended-remote 127.0.0.1:${UNI_GDB_PORT:-3333}" \
    -ex 'x/2wx 0xe000ed28' -ex 'detach' >"$physical/faults.log" 2>&1
rg -q '^0xe000ed28:\s+0x00000000\s+0x00000000' "$physical/faults.log"
