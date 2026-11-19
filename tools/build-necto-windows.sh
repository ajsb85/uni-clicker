#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

cube=${1:?Pass the STM32CubeF7 root}
windows=${UNI_WINDOWS_ROOT:?Source tools/bench-env.sh}
sdk=${NECTO_SDK_ROOT:?Set NECTO_SDK_ROOT}
toolchain=${NECTO_WIN_GCC_ROOT:-"$windows/NECTOStudio7/packages/compilers/gcc/arm/gcc-arm-none-eabi"}
work="$windows/.uni-clicker-lab-cache/necto-windows"
mkdir -p "$work" build/necto-windows

cmsis="$cube/Drivers/CMSIS"
device="$cmsis/Device/ST/STM32F7xx"
stm32="$sdk/targets/arm/mikroe/stm32"
common="$sdk/targets/arm/mikroe/common/include"

includes=(
    "$PWD/build/necto" "$cmsis/Include" "$device/Include"
    "$stm32/include" "$stm32/include/gpio" "$common"
    "$common/mcu_definitions/STM32/STM32F746ZGTx"
    "$common/mcu_reg_addresses/STM32/STM32F746ZG"
)
sources=(
    "$PWD/examples/necto/main.c"
    "$stm32/src/gpio/implementation_1/hal_ll_gpio_port.c"
    "$device/Source/Templates/gcc/startup_stm32f746xx.s"
    "$device/Source/Templates/system_stm32f7xx.c"
    "$PWD/firmware/startup_support.c"
)
flags=()
files=()
for path in "${includes[@]}"; do flags+=("-I$(wslpath -m "$path")"); done
for path in "${sources[@]}"; do files+=("$(wslpath -m "$path")"); done
linker=$(wslpath -m "$PWD/firmware/stm32f746.ld")
output=$(wslpath -m "$work")

# Under WSL, this GCC driver resolves cc1 relative to its Windows working directory.
(
    cd "$toolchain/bin"
    ./arm-none-eabi-gcc.exe -mcpu=cortex-m7 -mthumb -mfloat-abi=soft -g3 -Og \
        -ffunction-sections -fdata-sections -DSTM32F746xx -DSTM32F7xx \
        -D__hal_ll_gpio_subset_1__ -nostdlib "-T$linker" \
        "-Wl,--gc-sections,-z,noexecstack,-Map,$output/hello.map" \
        "${flags[@]}" "${files[@]}" -o "$output/hello.elf"
)
cp "$work"/hello.{elf,map} build/necto-windows/
