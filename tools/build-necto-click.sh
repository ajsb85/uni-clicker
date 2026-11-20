#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source tools/bench-env.sh

board=${1:?Pass the Click driver ID}
compiler=${2:-gcc}
if [[ ! "$board" =~ ^[a-z0-9_]+$ || ! "$compiler" =~ ^(gcc|necto)$ ]]; then
    echo "Usage: tools/build-necto-click.sh <driver-id> [gcc|necto]" >&2
    exit 2
fi

sdk="$(realpath "$NECTO_SDK_ROOT")"
sdk_arm="$sdk/targets/arm/mikroe"
stm32="$sdk_arm/stm32"
common="$sdk_arm/common/include"
cmsis="$(realpath "${STM32CUBE_F7:-.cache/vendor/STM32CubeF7}")/Drivers/CMSIS"
device="$cmsis/Device/ST/STM32F7xx"
shim="$PWD/examples/necto-click"
out="$PWD/build/clicks/$board/$compiler"
mkdir -p "$out"
sed 's/@MACRO_LIST1@@MACRO_LIST2@/#define FLATTEN_ME_LEVEL FLATTEN_ME_LEVEL_NONE/' \
    "$sdk/cmake/InstallHeadersFlatten.cmake.in" >"$out/flatten_me.h"
printf '#include <stm32f7xx.h>\n' >"$out/core_header.h"

includes=(
    "$shim" "$out" "$cmsis/Include" "$device/Include"
    "$stm32/include" "$stm32/include/gpio"
    "$common" "$common/mcu_definitions/STM32/STM32F746ZGTx"
    "$common/mcu_reg_addresses/STM32/STM32F746ZG"
    "$sdk/hal/interface" "$sdk/hal/lib/include" "$sdk/drv/lib/include"
)
sources=(
    "$shim/board.c"
    "$sdk/drv/lib/src/lib_drv_digital_in/drv_digital_in.c"
    "$sdk/hal/lib/src/lib_hal_gpio/hal_gpio.c"
    "$stm32/src/gpio/hal_ll_gpio.c"
    "$stm32/src/gpio/implementation_1/hal_ll_gpio_port.c"
    "$device/Source/Templates/gcc/startup_stm32f746xx.s"
    "$device/Source/Templates/system_stm32f7xx.c" "$PWD/firmware/startup_support.c"
)
flags=(-mcpu=cortex-m7 -mthumb -mfloat-abi=soft -g3 -Og -ffunction-sections -fdata-sections
    -DSTM32F746xx -DSTM32F7xx -D__hal_ll_gpio_subset_1__
    -Wno-error=int-conversion -Wno-error=incompatible-pointer-types
    -nostartfiles -specs=nano.specs -specs=nosys.specs -Wl,--gc-sections,-z,noexecstack,-u,_printf_float)
linker="$PWD/firmware/stm32f746.ld"
output="$out"
cc=("${STM32_GCC:-arm-none-eabi-gcc}")

case "$board" in
    thermo28)
        corpus="$(realpath "${MIKROSDK_CLICK_ROOT:-.cache/vendor/mikrosdk-click-v2}")"
        click="$corpus/clicks/$board"
        includes+=("$stm32/include/i2c" "$stm32/include/i2c/hal_ll_i2c_pin_map/implementation_2"
            "$click/lib_$board/include")
        sources+=("$click/example/main.c" "$click/lib_$board/src/$board.c"
            "$sdk/drv/lib/src/lib_drv_i2c_master/drv_i2c_master.c"
            "$sdk/hal/lib/src/lib_hal_i2c_master/hal_i2c_master.c"
            "$stm32/src/i2c/implementation_2/hal_ll_i2c_master.c")
        flags+=(-D__hal_ll_i2c_subset_2__)
        ;;
    lan8651)
        includes+=("$stm32/include/spi_master" "$stm32/include/spi_master/hal_ll_spi_master_pin_map/implementation_1")
        sources+=("$shim/lan8651.c"
            "$sdk/drv/lib/src/lib_drv_digital_out/drv_digital_out.c"
            "$sdk/drv/lib/src/lib_drv_spi_master/drv_spi_master.c"
            "$sdk/hal/lib/src/lib_hal_spi_master/hal_spi_master.c"
            "$stm32/src/spi_master/implementation_1/hal_ll_spi_master.c")
        flags+=(-D__hal_ll_spi_master_subset_1__)
        ;;
    *) echo "No UNI Clicker build configured for $board" >&2; exit 2 ;;
esac

if [[ "$compiler" == necto ]]; then
    toolchain="${NECTO_WIN_GCC_ROOT:-$UNI_WINDOWS_ROOT/NECTOStudio7/packages/compilers/gcc/arm/gcc-arm-none-eabi}"
    for i in "${!includes[@]}"; do includes[i]="$(wslpath -m "${includes[i]}")"; done
    for i in "${!sources[@]}"; do sources[i]="$(wslpath -m "${sources[i]}")"; done
    linker="$(wslpath -m "$linker")"
    output="$(wslpath -m "$out")"
    # NECTO's Windows GCC uses its working directory to locate cc1.
    cd "$toolchain/bin"
    cc=(./arm-none-eabi-gcc.exe)
fi

for path in "${includes[@]}"; do flags+=("-I$path"); done
"${cc[@]}" --version >"$out/compiler.txt"
"${cc[@]}" "${flags[@]}" "-T$linker" "-Wl,-Map,$output/example.map" \
    "${sources[@]}" -o "$output/example.elf"
"${OBJCOPY:-arm-none-eabi-objcopy}" -O ihex "$out/example.elf" "$out/example.hex"
echo "Built $out/example.elf"
