#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "${1:-}" == nanoframework-native ]]; then
    shift
    exec tools/simulate-nanoframework.sh "$@"
fi
usage() {
    echo 'Usage: tools/simulate.sh <profile> [smoke|gpio|trace|gdb]' >&2
    exit 2
}
platform=uni-clicker.repl
case "${1:-}" in
    stm32cube) language=STM32Cube; artifact=hello.elf ;;
    arduino) language=Arduino; artifact=HelloUni.ino.elf ;;
    rust) language=Rust; artifact=hello.elf ;;
    swift) language='Embedded Swift'; artifact=hello.elf ;;
    zig) language=Zig; artifact=hello.elf ;;
    necto|necto-windows) language=NECTO; artifact=hello.elf ;;
    mikroc|mikroc-source-check) language=mikroC; artifact=hello.elf ;;
    freertos) language=FreeRTOS; artifact=hello.elf ;;
    threadx) language=ThreadX; artifact=hello.elf ;;
    libopencm3) language=libopencm3; artifact=hello.elf ;;
    riot) language=RIOT; artifact=hello.elf ;;
    chibios) language=ChibiOS; artifact=hello.elf ;;
    zephyr) language=Zephyr; artifact=hello.elf ;;
    cmsis) language=CMSIS; artifact=hello.elf ;;
    mbed-os) language='Mbed OS'; artifact=hello.elf; platform=uni-clicker-pll.repl ;;
    micropython) language=MicroPython; artifact=firmware/firmware.elf; platform=uni-clicker-pll.repl ;;
    nuttx) language=NuttX; artifact=hello.elf; platform=uni-clicker-pll.repl ;;
    *) usage ;;
esac

mode=${2:-smoke}
case "$mode" in
    smoke|gpio|trace|gdb) ;;
    *) usage ;;
esac
[[ $# -le 2 ]] || usage
if [[ "$1" == nuttx && "$mode" == gpio ]]; then
    echo 'The NuttX example prints once during startup.' >&2
    exit 2
fi

binary="${UNI_SIM_ELF:-$PWD/build/$1/$artifact}"
if [[ ! -f "$binary" ]]; then
    echo "Run make $1 first." >&2
    exit 1
fi
export TMPDIR="$PWD/.cache/tmp"
mkdir -p "$TMPDIR" .cache/sim
run=$(mktemp -d "$PWD/.cache/sim/$1.$mode.XXXXXX")
cat > "$run/run.resc" <<SCRIPT
mach create "uni-clicker"
machine LoadPlatformDescription "$PWD/sim/$platform"
sysbus LoadELF "$binary"
cpu VectorTableOffset 0x08000000
usart6 CreateFileBackend "$run/uart.txt"
SCRIPT

case "$mode" in
    smoke)
        printf 'emulation RunFor "1.4"\nquit\n' >> "$run/run.resc"
        ;;
    gpio)
        cat >> "$run/run.resc" <<'SCRIPT'
emulation RunFor "0.6"
sysbus ReadDoubleWord 0x40020c14
emulation RunFor "0.6"
sysbus ReadDoubleWord 0x40020c14
emulation RunFor "0.5"
sysbus ReadDoubleWord 0x40020c14
quit
SCRIPT
        ;;
    trace)
        cat >> "$run/run.resc" <<SCRIPT
using sysbus
sysbus LogPeripheralAccess usart6 true
cpu CreateExecutionTracing "boot" "$run/boot.trace" PCAndOpcode
emulation RunFor "0.002"
cpu DisableExecutionTracing
quit
SCRIPT
        ;;
    gdb)
        printf 'machine StartGdbServer 3334\n' >> "$run/run.resc"
        printf 'GDB endpoint 127.0.0.1:3334\nUART output %s/uart.txt\n' "$run"
        exec "${RENODE:-renode}" --console --disable-gui --plain \
            --config "$run/renode.config" "$run/run.resc"
        ;;
esac

if ! timeout --kill-after=2s 30s "${RENODE:-renode}" --console --disable-gui --plain \
    --config "$run/renode.config" "$run/run.resc" </dev/null >"$run/renode.log" 2>&1; then
    cat "$run/renode.log" >&2
    exit 1
fi

case "$mode" in
    gpio)
        mapfile -t samples < <(tr -d '\r' < "$run/renode.log" | sed -n 's/^\(0x[0-9A-Fa-f]\{8\}\)$/\1/p')
        if (( ${#samples[@]} != 3 )) || (( samples[0] != 0x80 || samples[1] != 0 || samples[2] != 0x80 )); then
            echo "Unexpected GPIO samples. Inspect $run/renode.log." >&2
            exit 1
        fi
        printf 'PD7 at 0.6, 1.2, and 1.7 virtual seconds: high, low, high\n'
        exit 0
        ;;
    trace)
        test -s "$run/boot.trace"
        printf 'CPU trace %s/boot.trace\nPeripheral log %s/renode.log\n' "$run" "$run"
        exit 0
        ;;
esac

printf 'Hello, UNI Clicker from %s!\r\n' "$language" > "$run/expected.txt"
if [[ "$1" != nuttx ]]; then
    printf 'Hello, UNI Clicker from %s!\r\n' "$language" >> "$run/expected.txt"
fi
if ! cmp -s "$run/expected.txt" "$run/uart.txt"; then
    echo "Unexpected USART6 output. Inspect $run/uart.txt and $run/renode.log." >&2
    exit 1
fi
cat "$run/uart.txt"
