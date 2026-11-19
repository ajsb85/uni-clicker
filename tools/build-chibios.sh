#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/examples/frameworks/chibios"
sdk=${CHIBIOS_ROOT:?Set CHIBIOS_ROOT or source tools/bench-env.sh}
demo="$sdk/demos/STM32/RT-STM32F746ZG-NUCLEO144"
out="$PWD/build/chibios"
stage="$out/project"
mkdir -p "$stage/cfg"
cp "$demo/Makefile" "$stage/"
cp "$demo"/cfg/*.h "$stage/cfg/"
cp "$app/main.c" "$stage/main.c"

sed -i -E \
    -e 's/^(#define STM32_(HSE_ENABLED|LSE_ENABLED|CLOCK48_REQUIRED|SERIAL_USE_USART3)) +TRUE/\1 FALSE/' \
    -e 's/^(#define STM32_SERIAL_USE_USART6) +FALSE/\1 TRUE/' \
    -e 's/^(#define STM32_SW) +STM32_SW_PLL/\1 STM32_SW_HSI/' \
    -e 's/^(#define STM32_PLLSRC) +STM32_PLLSRC_HSE/\1 STM32_PLLSRC_HSI/' \
    -e 's/^(#define STM32_PLLM_VALUE) +8/\1 16/' \
    -e 's/^(#define STM32_PPRE[12]) +STM32_PPRE([12])_DIV[24]/\1 STM32_PPRE\2_DIV1/' \
    -e 's/^(#define STM32_RTCSEL) +STM32_RTCSEL_LSE/\1 STM32_RTCSEL_NOCLOCK/' \
    -e 's/^(#define STM32_CECSEL) +STM32_CECSEL_LSE/\1 STM32_CECSEL_HSIDIV488/' \
    "$stage/cfg/mcuconf.h"
sed -i -E \
    -e 's/^(#define CH_CFG_ST_TIMEDELTA) +2/\1 0/' \
    -e 's/^(#define CH_CFG_ST_FREQUENCY) +10000/\1 1000/' \
    "$stage/cfg/chconf.h"

make -C "$stage" CHIBIOS="$sdk" BOARDSRC="$app/board.c" TESTSRC= \
    USE_LTO=no USE_OPT='-Og -g' -j"${UNI_JOBS:-4}"
cp "$stage/build/ch.elf" "$out/hello.elf"
