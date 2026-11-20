# Source this file from Bash.
uni_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export UNI_WINDOWS_ROOT="${UNI_WINDOWS_ROOT:-/mnt/c/Users/gbast/dev/uni-clicker}"
uni_assets="$UNI_WINDOWS_ROOT/.uni-clicker-lab-cache"

export TMPDIR="$uni_root/.cache/tmp"
export CUBE_PROG="${CUBE_PROG:-$UNI_WINDOWS_ROOT/STM32CubeProgrammer/bin/STM32_Programmer_CLI.exe}"
export OPENOCD="${OPENOCD:-$uni_assets/xpack-openocd-0.12.0-7/bin/openocd.exe}"
export OPENOCD_SCRIPTS="${OPENOCD_SCRIPTS:-$uni_assets/xpack-openocd-0.12.0-7/openocd/scripts}"
export PROBE_RS="${PROBE_RS:-$uni_assets/probe-rs/v0.32.0/probe-rs.exe}"
uni_segger="$uni_assets/segger"
if [[ ! -d "$uni_segger/SystemView/.git" || ! -d "$uni_segger/RTT/.git" ]]; then
    uni_segger="$uni_root/.cache/vendor/segger"
fi
export SEGGER_SYSTEMVIEW_ROOT="${SEGGER_SYSTEMVIEW_ROOT:-$uni_segger/SystemView}"
export SEGGER_RTT_ROOT="${SEGGER_RTT_ROOT:-$uni_segger/RTT}"
export RENODE="${RENODE:-$uni_root/.cache/tools/renode/renode}"
export SWIFTC="${SWIFTC:-$uni_assets/swift/usr/bin/swiftc}"
export ARDUINO_DIRECTORIES_DATA="${ARDUINO_DIRECTORIES_DATA:-$uni_root/.cache/arduino-fast-data}"
export ARDUINO_DIRECTORIES_DOWNLOADS="${ARDUINO_DIRECTORIES_DOWNLOADS:-$uni_assets/arduino-data/staging}"
export ARDUINO_DIRECTORIES_USER="${ARDUINO_DIRECTORIES_USER:-$uni_root/.cache/arduino-user}"
export MICROZIG="${MICROZIG:-$UNI_WINDOWS_ROOT/microzig}"
export ZIG_LOCAL_PKG_DIR="${ZIG_LOCAL_PKG_DIR:-$uni_assets/zig/packages}"
export NECTO_SDK_ROOT="${NECTO_SDK_ROOT:-$UNI_WINDOWS_ROOT/NECTOStudio7/packages/sdk/mikroSDK_v2/src}"
export MIKROC_ARM_ROOT="${MIKROC_ARM_ROOT:-$UNI_WINDOWS_ROOT/mikroC PRO for ARM}"

export FREERTOS_ROOT="${FREERTOS_ROOT:-$UNI_WINDOWS_ROOT/NECTOStudio7/packages/freertos/freertos_1130}"
export THREADX_ROOT="${THREADX_ROOT:-$uni_assets/frameworks/threadx}"
export OPENCM3="${OPENCM3:-$uni_assets/frameworks/libopencm3}"
uni_sdk="$uni_assets/frameworks"
uni_pio="$uni_assets/platformio-core"
if mountpoint -q "$uni_root/.cache/sdk-native"; then
    uni_sdk="$uni_root/.cache/sdk-native"
    uni_pio="$uni_sdk/platformio-core"
    export TMPDIR="$uni_sdk/scratch"
    export ZEPHYR_BUILD_DIR="${ZEPHYR_BUILD_DIR:-$uni_sdk/zephyr-build}"
    export MBED_BUILD_DIR="${MBED_BUILD_DIR:-$uni_sdk/mbed-build}"
    export RUST_BUILD_DIR="${RUST_BUILD_DIR:-$uni_sdk/work/rust-hello}"
fi
export CHIBIOS_ROOT="${CHIBIOS_ROOT:-$uni_assets/frameworks/ChibiOS-21.11}"
export ZEPHYR_WORKSPACE="${ZEPHYR_WORKSPACE:-$uni_sdk/zephyr-workspace}"
export NUTTX_WORKSPACE="${NUTTX_WORKSPACE:-$uni_sdk/nuttx-workspace}"
export MBED_OS_ROOT="${MBED_OS_ROOT:-$uni_sdk/mbed-os-6.17}"
export FRAMEWORK_PYTHON="${FRAMEWORK_PYTHON:-$uni_root/.cache/framework-venv/bin/python}"
if [[ -f "$uni_sdk/micropython-1.25/ports/stm32/Makefile" ]]; then
    export MICRO_PYTHON_ROOT="${MICRO_PYTHON_ROOT:-$uni_sdk/micropython-1.25}"
else
    export MICRO_PYTHON_ROOT="${MICRO_PYTHON_ROOT:-$uni_assets/frameworks/micropython-1.25}"
fi
export PLATFORMIO="${PLATFORMIO:-$uni_root/.cache/platformio-venv/bin/pio}"
export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-$uni_pio}"

mkdir -p "$TMPDIR"
unset uni_root uni_assets uni_sdk uni_pio uni_segger
