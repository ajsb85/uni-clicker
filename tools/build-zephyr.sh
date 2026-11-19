#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
workspace=${ZEPHYR_WORKSPACE:?Set ZEPHYR_WORKSPACE or source tools/bench-env.sh}
python=${FRAMEWORK_PYTHON:-python3}
out="${ZEPHYR_BUILD_DIR:-build/zephyr/sdk}"
export ZEPHYR_BASE="$workspace/zephyr"
export ZEPHYR_TOOLCHAIN_VARIANT=cross-compile
export CROSS_COMPILE="${CROSS_COMPILE:-$(command -v arm-none-eabi-gcc | sed 's/gcc$//')}"
modules="$workspace/modules/hal"
cmake -S examples/frameworks/zephyr -B "$out" -G Ninja \
    -DBOARD=nucleo_f746zg -DPython3_EXECUTABLE="$python" \
    -DZEPHYR_MODULES="$modules/cmsis;$modules/cmsis_6;$modules/stm32"
cmake --build "$out" --parallel "${UNI_JOBS:-4}"
mkdir -p build/zephyr
cp "$out/zephyr/zephyr.elf" build/zephyr/hello.elf
