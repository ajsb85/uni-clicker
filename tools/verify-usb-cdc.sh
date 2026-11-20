#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/bench-env.sh
if [[ $# -ne 2 || "$1" != --hardware || ! -f "$2" ]]; then
    echo 'Usage: tools/verify-usb-cdc.sh --hardware path/to/UsbCdcUni.ino.elf' >&2
    exit 2
fi

elf=$(realpath "$2")
mkdir -p .cache/verification
out=$(mktemp -d "$PWD/.cache/verification/usb-cdc.XXXXXX")
printf 'USB CDC bench report %s\n' "$out"
sha256sum "$elf" >"$out/elf.sha256"
exec 9>.cache/probe.lock
flock -n 9 || { echo 'Another bench run owns the probe.' >&2; exit 1; }
port=${UNI_GDB_PORT:-3333}
gdb=${GDB:-gdb-multiarch}
image=$elf
if [[ "$OPENOCD" == *.exe ]]; then
    image=$(wslpath -m "$elf")
fi
debug/start-openocd.sh \
    -c 'reset halt' \
    -c 'if {([lindex [read_memory 0xe0042000 32 1] 0] & 0xfff) != 0x449 || [lindex [read_memory 0x1ff0f442 16 1] 0] != 1024} {error "Expected STM32F746ZG with 1 MiB flash"}' \
    -c "program {$image} verify reset" >"$out/openocd.log" 2>&1 &
server=$!
ready=false
cleanup() {
    if [[ "$ready" == true ]]; then
        timeout 5s "$gdb" -q -nx -batch -ex 'set remotetimeout 2' \
            -ex "target extended-remote 127.0.0.1:$port" -ex 'monitor resume' \
            -ex 'monitor shutdown' >"$out/shutdown.log" 2>&1 || true
    fi
    kill "$server" 2>/dev/null || true
    wait "$server" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for ((attempt=0; attempt<150; ++attempt)); do
    kill -0 "$server" 2>/dev/null || break
    if rg -q 'Verified OK' "$out/openocd.log"; then
        ready=true
        break
    fi
    sleep 0.1
done
[[ "$ready" == true ]] || { echo "USB CDC flash verification failed. See $out/openocd.log" >&2; exit 1; }
timeout --kill-after=2s 20s "$gdb" -q -nx -batch "$elf" -ex 'set remotetimeout 3' \
    -ex "target extended-remote 127.0.0.1:$port" -x debug/verify-usb-cdc.gdb |
    tee "$out/gdb.log"
