#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/bench-env.sh
destination="$PWD/.cache/references/uni-clicker"
mkdir -p "$destination"

documents=(
    SiBRAIN-for-STM32F746ZG-Schematic
    sibrain-standard-guidelines-2021-10-6
    uni-clicker-manual
    UNI-clicker-schematic-web
)
for name in "${documents[@]}"; do
    input="$UNI_WINDOWS_ROOT/$name.pdf"
    pdftotext -layout "$input" "$destination/$name.txt"
    if [[ "$name" =~ [Ss]chematic ]]; then
        pdftoppm -r 125 -png "$input" "$destination/$name"
    fi
done
cat >"$destination/README.md" <<'MD'
# UNI Clicker board reference exports

Search the layout-preserving text with `rg -ni 'USB.PSW|USB_N|USB_P|PA11|PA12|VBUS' *.txt`.
Open the corresponding schematic PNG page to follow wires, resistors and connector pins.
The source PDFs are in the Windows workspace root.

| Reference | Pages to consult | Local exports |
| --- | --- | --- |
| SiBRAIN for STM32F746ZG schematic | MCU and socket wiring, USB_FS and oscillator | [Text](SiBRAIN-for-STM32F746ZG-Schematic.txt), [page 1](SiBRAIN-for-STM32F746ZG-Schematic-1.png) |
| SiBRAIN standard guidelines | Connector pin conventions and card design | [Text](sibrain-standard-guidelines-2021-10-6.txt) |
| UNI Clicker manual | Connectivity and USB mode on printed pages 12–13 | [Text](uni-clicker-manual.txt) |
| UNI Clicker baseboard schematic | USB-C and power switch on page 1, socket and expansion pins on page 2 | [Text](UNI-clicker-schematic-web.txt), [page 1](UNI-clicker-schematic-web-1.png), [page 2](UNI-clicker-schematic-web-2.png) |

Regenerate from the repository root with `tools/export-board-references.sh`.
MD
printf 'Board reference exports %s\n' "$destination"
