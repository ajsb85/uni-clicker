#!/usr/bin/env bash
set -euo pipefail

destination=${1:?Usage: fetch-stm32cube.sh DESTINATION}
revision=767d083e202412da7f50f11515bf3fa1be2cf4fe
if [[ ! -d "$destination/.git" ]]; then
    mkdir -p "$destination"
    git -C "$destination" init -q
    git -C "$destination" remote add origin https://github.com/STMicroelectronics/STM32CubeF7.git
fi
git -C "$destination" sparse-checkout set --no-cone \
    '/.gitmodules' \
    '/Drivers/CMSIS/Include/' \
    '/Drivers/CMSIS/Device/ST/STM32F7xx/' \
    '/Drivers/STM32F7xx_HAL_Driver/'
if ! git -C "$destination" cat-file -e "$revision^{commit}" 2>/dev/null; then
    git -C "$destination" fetch --depth 1 origin "$revision"
fi
git -C "$destination" checkout --detach "$revision"
git -C "$destination" submodule update --init --depth 1 \
    Drivers/CMSIS/Device/ST/STM32F7xx Drivers/STM32F7xx_HAL_Driver
