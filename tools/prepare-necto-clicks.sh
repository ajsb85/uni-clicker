#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

case "${1:-}" in
    ""|--drivers-only|--compatibility) ;;
    *) echo "Usage: $0 [--drivers-only|--compatibility]" >&2; exit 2 ;;
esac

checkout() {
    local path="$1" url="$2" revision="$3"
    shift 3
    if [[ ! -d "$path/.git" ]]; then
        git init -q "$path"
        git -C "$path" remote add origin "$url"
        git -C "$path" config remote.origin.promisor true
        git -C "$path" config remote.origin.partialclonefilter blob:none
        git -C "$path" sparse-checkout set "$@"
        git -C "$path" fetch --depth 1 --filter=blob:none origin "$revision"
        git -C "$path" checkout --detach FETCH_HEAD
    fi
    if [[ "$(git -C "$path" rev-parse HEAD)" != "$revision" ]]; then
        echo "Expected $path at $revision" >&2
        exit 1
    fi
    git -C "$path" sparse-checkout add "$@"
}

mapfile -t drivers < <(python3 - "${1:-}" <<'PYTHON'
import json
from pathlib import Path
import sys
drivers = set(json.loads(Path("examples/necto-click/cohort.json").read_text()))
if sys.argv[1] == "--compatibility":
    drivers.update(json.loads(Path("examples/necto-click/compatibility.json").read_text())["drivers"])
for file in Path("sim/clicks").glob("*.json"):
    driver = json.loads(file.read_text()).get("driver")
    if driver:
        drivers.add(driver)
for driver in sorted(drivers):
    print(f"clicks/{driver}")
PYTHON
)

checkout .cache/vendor/mikrosdk-click-v2 https://github.com/MikroElektronika/mikrosdk_click_v2.git \
    c261a018eb4aaaadc674131ceb3893e301384783 "${drivers[@]}"

if [[ "${1:-}" != --drivers-only ]]; then
    checkout .cache/vendor/mikrosdk-v2 https://github.com/MikroElektronika/mikrosdk_v2.git \
        6bcf71dff049316688475ff691f7ec24bcd50d05 cmake drv hal \
        targets/arm/mikroe/stm32 targets/arm/mikroe/common targets/arm/mikroe/core platform/ring platform/conversions \
        components/ethernet/w5500_wizip55 middleware/ethernet/core middleware/ethernet/spi middleware/ethernet/net \
        middleware/physical_drive middleware/filesystem
fi
