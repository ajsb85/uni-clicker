#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source tools/bench-env.sh

if [[ "${1:-}" != --flash ]]; then
    echo "Usage: tools/check-lan8651-bench.sh --flash [firmware-directory]" >&2
    exit 2
fi
firmware="${2:-build/clicks/lan8651/necto}"
test -s "$firmware/example.elf" && test -s "$firmware/example.hex" || {
    echo "Build the LAN8651 probe with tools/build-necto-click.sh first." >&2
    exit 1
}

mkdir -p .cache/verification .cache/clicks
out="$(mktemp -d "$PWD/.cache/verification/lan8651-bench.XXXXXX")"
private="$(mktemp -d "$PWD/.cache/clicks/lan8651-backup.XXXXXX")"
echo "Bench report in $out"
exec 9>.cache/probe.lock
flock -n 9 || { echo "Another bench run owns the probe." >&2; exit 1; }

cp "$firmware/example.elf" "$firmware/example.hex" "$private/"
symbol="$(arm-none-eabi-nm "$private/example.elf" | awk '$3 == "lan8651_result" {print "0x" $1}')"
[[ "$symbol" =~ ^0x200[0-4][0-9a-f]{4}$ ]]
(
    cd "$private"
    sha256sum example.elf example.hex
) >"$out/firmware.sha256"

programmer() {
    local logfile="$1"
    shift
    timeout --kill-after=2s 90s "$CUBE_PROG" "$@" 2>&1 |
        sed -E '/(ST-LINK SN|Serial [Nn]umber)[[:space:]]*:/d' >"$logfile"
}

backup="$private/original.bin"
programmer "$out/backup.log" -c port=SWD mode=HOTPLUG \
    -u 0x08000000 0x100000 "$(wslpath -w "$backup")"
[[ "$(stat -c %s "$backup")" == 1048576 ]]

restore() {
    local status=$?
    trap - EXIT
    if ! programmer "$out/restore.log" -c port=SWD mode=UR \
        -d "$(wslpath -w "$backup")" 0x08000000 -v -rst; then
        echo "Flash restore failed. Original image is in $backup." >&2
        exit 1
    fi
    if ! programmer "$out/restore-read.log" -c port=SWD mode=HOTPLUG \
        -u 0x08000000 0x100000 "$(wslpath -w "$private/restored.bin")" ||
        ! cmp -s "$backup" "$private/restored.bin"; then
        echo "Flash restore readback differed. Original image is in $backup." >&2
        exit 1
    fi
    echo "Original flash restored and read back byte for byte"
    exit "$status"
}
trap restore EXIT

programmer "$out/flash.log" -c port=SWD mode=UR \
    -d "$(wslpath -w "$private/example.hex")" -v -rst
sleep 0.2
programmer "$out/read.log" -c port=SWD mode=HOTPLUG \
    -u "$symbol" 44 "$(wslpath -w "$out/result.bin")"

python3 - "$out/result.bin" <<'PYTHON'
import json
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
names = ("result", "idver", "devid", "initial_status", "initial_irq", "protected_id",
         "cleared_status", "cleared_irq", "footer", "acknowledged_irq", "reset_status")
result = dict(zip(names, struct.unpack("<11I", path.read_bytes()), strict=True))
formatted = {name: f"0x{value:08X}" for name, value in result.items()}
path.with_suffix(".json").write_text(json.dumps(formatted, indent=2) + "\n")
print(json.dumps(formatted, indent=2))
if not (result["result"] == 0x86510000 and result["idver"] == 0x11
        and result["devid"] >> 4 == 0x8651 and result["devid"] == result["protected_id"]
        and result["initial_status"] & 0x40 and result["initial_irq"] == 0
        and not result["cleared_status"] & 0x40 and result["cleared_irq"] == 0
        and result["footer"].bit_count() % 2 == 1 and not result["footer"] & 0xc0200000
        and result["acknowledged_irq"] == 1
        and result["reset_status"] & 0x40):
    raise SystemExit("LAN8651 hardware probe did not satisfy the reset and SPI contract")
PYTHON
