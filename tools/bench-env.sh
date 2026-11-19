# Source this file from Bash.
uni_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export UNI_WINDOWS_ROOT="${UNI_WINDOWS_ROOT:-/mnt/c/Users/gbast/dev/uni-clicker}"
uni_assets="$UNI_WINDOWS_ROOT/.uni-clicker-lab-cache"

export TMPDIR="$uni_root/.cache/tmp"
export CUBE_PROG="${CUBE_PROG:-$UNI_WINDOWS_ROOT/STM32CubeProgrammer/bin/STM32_Programmer_CLI.exe}"
export OPENOCD="${OPENOCD:-$uni_assets/xpack-openocd-0.12.0-7/bin/openocd.exe}"
export OPENOCD_SCRIPTS="${OPENOCD_SCRIPTS:-$uni_assets/xpack-openocd-0.12.0-7/openocd/scripts}"
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

mkdir -p "$TMPDIR"
unset uni_root uni_assets
