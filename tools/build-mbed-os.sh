#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk=${MBED_OS_ROOT:?Set MBED_OS_ROOT or source tools/bench-env.sh}
app="$PWD/examples/frameworks/mbed-os"
out="$PWD/build/mbed-os"
work="${MBED_BUILD_DIR:-$out/sdk}"
python=${FRAMEWORK_PYTHON:-python3}
mbed_tools=${MBED_TOOLS:-$(dirname "$python")/mbed-tools}
if [[ "$mbed_tools" == ./mbed-tools ]]; then mbed_tools=mbed-tools; fi
mkdir -p "$work"
"$mbed_tools" configure -m NUCLEO_F746ZG -t GCC_ARM -b debug -p "$app" \
    --mbed-os-path "$sdk" -o "$work"
cmake -S "$app" -B "$work" -G Ninja -Wno-dev \
    -DMBED_PATH="$sdk" -DMBED_TARGET=NUCLEO_F746ZG -DMBED_TOOLCHAIN=GCC_ARM
cmake --build "$work" --parallel "${UNI_JOBS:-4}"
mkdir -p "$out"
cp "$work/uni_clicker_hello.elf" "$out/hello.elf"
