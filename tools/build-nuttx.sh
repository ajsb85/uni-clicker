#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
lab=$PWD
workspace=${NUTTX_WORKSPACE:?Set NUTTX_WORKSPACE to writable NuttX and Apps trees}
app="$workspace/apps/examples/uni_hello"
mkdir -p "$app" "$lab/build/nuttx"
cp examples/frameworks/nuttx/{Kconfig,Make.defs,Makefile,unihello_main.c} "$app/"

if [[ -x "$lab/.cache/kconfig-frontends/usr/bin/kconfig-conf" ]]; then
    export PATH="$lab/.cache/kconfig-frontends/usr/bin:$PATH"
    export LD_LIBRARY_PATH="$lab/.cache/kconfig-frontends/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

cd "$workspace/nuttx"
if [[ ! -f .config ]]; then
    tools/configure.sh -l -a ../apps nucleo-f746zg:nsh
fi
if ! grep -qx 'CONFIG_ARCH_BOARD="nucleo-f746zg"' .config; then
    echo 'Use a dedicated NuttX workspace configured for nucleo-f746zg:nsh.' >&2
    exit 1
fi

board=boards/arm/stm32f7/nucleo-f746zg/include/board.h
if ! grep -q '^#define STM32_BOARD_USEHSI 1$' "$board"; then
    sed -i -E \
        -e '/^#define STM32_HSI_FREQUENCY/a #define STM32_BOARD_USEHSI 1' \
        -e 's/(RCC_PLLCFG_PLLM)\(4\)/\1(8)/' \
        -e 's/\(STM32_HSE_FREQUENCY \/ 4\)/(STM32_HSI_FREQUENCY \/ 8)/' \
        -e 's/(GPIO_USART6_(TX|RX))_2/\1_1/' "$board"
fi

if ! grep -qx 'CONFIG_INIT_ENTRYPOINT="unihello_main"' .config ||
    grep -qx 'CONFIG_STM32F7_USART3=y' .config; then
    sed -i -E '/^(# )?CONFIG_(EXAMPLES_UNI_HELLO|INIT_ENTRYPOINT|NUCLEO_F746ZG_CONSOLE_(VIRTUAL|ARDUINO)|STM32F7_USART3|USART3_SERIALDRIVER|USART[36]_SERIAL_CONSOLE)(=| )/d' .config
    cat >>.config <<'CONFIG'
CONFIG_EXAMPLES_UNI_HELLO=y
CONFIG_INIT_ENTRYPOINT="unihello_main"
CONFIG_NUCLEO_F746ZG_CONSOLE_ARDUINO=y
CONFIG_USART6_SERIAL_CONSOLE=y
CONFIG
    make olddefconfig
fi
make -j"${UNI_JOBS:-4}"
cp nuttx "$lab/build/nuttx/hello.elf"
