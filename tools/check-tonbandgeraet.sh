#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/bench-env.sh
if [[ $# != 2 || ! "$1" =~ ^(stm32cube|freertos)$ ]]; then
    echo 'Usage: tools/check-tonbandgeraet.sh <stm32cube|freertos> <output-dir>' >&2
    exit 2
fi
profile=$1
mkdir -p "$2"
out=$(realpath "$2")
printf 'Trace run %s\n' "$out"
tonband="${TONBAND_ROOT:-$UNI_WINDOWS_ROOT/Tonbandgeraet}"
test -f "$tonband/tband/src/tband.c" || { echo "Set TONBAND_ROOT to the Tonbandgeraet checkout." >&2; exit 1; }

if [[ -n "${TBAND_CLI:-}" ]]; then
    cli=$TBAND_CLI
elif [[ -z "${TONBAND_ROOT:-}" && -r .cache/tonbandgeraet-stage ]] &&
     [[ -x "$(cat .cache/tonbandgeraet-stage)/target/debug/tband-cli" ]]; then
    cli="$(cat .cache/tonbandgeraet-stage)/target/debug/tband-cli"
else
    target="$PWD/.cache/tonbandgeraet-converter"
    if mountpoint -q .cache/sdk-native; then
        target="$PWD/.cache/sdk-native/work/tonbandgeraet-converter"
    fi
    CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0 cargo build --locked \
        --manifest-path "$tonband/tools/Cargo.toml" --target-dir "$target" \
        -p tband-cli --no-default-features
    cli="$target/debug/tband-cli"
fi

sdk="${STM32CUBE_F7:-$PWD/.cache/vendor/STM32CubeF7}"
case "$profile" in
    stm32cube)
        make tband-stm32cube TRACE_BUILD_DIR="$out" STM32CUBE_F7="$sdk" TONBAND_ROOT="$tonband" >"$out/build.log" 2>&1
        mode=bare-metal
        greeting=STM32Cube
        ;;
    freertos)
        {
            cmake -S examples/frameworks -B "$out" -G Ninja \
                -DCMAKE_TOOLCHAIN_FILE="$PWD/examples/necto/arm-gcc.cmake" \
                -DSTM32CUBE_F7="$sdk" -DFRAMEWORK=freertos -DKERNEL_DIR="$FREERTOS_ROOT" \
                -DTONBAND_ROOT="$tonband"
            cmake --build "$out"
        } >"$out/build.log" 2>&1
        mode=free-rtos
        greeting=FreeRTOS
        ;;
esac

elf="$out/hello.elf"
read -r address size < <(arm-none-eabi-nm -S "$elf" | awk '$4 == "uni_trace_capture" {print "0x" $1, "0x" $2}')
cat > "$out/run.resc" <<SCRIPT
mach create "uni-tband"
machine LoadPlatformDescription "$PWD/sim/uni-clicker.repl"
sysbus LoadELF "$elf"
cpu VectorTableOffset 0x08000000
usart6 CreateFileBackend "$out/uart.txt"
emulation RunFor "1.3"
dump_file $address $((size)) "$out/sram.bin"
sysbus ReadDoubleWord 0xE000ED28
sysbus ReadDoubleWord 0xE000ED2C
quit
SCRIPT
timeout --kill-after=2s 40s "$RENODE" --console --disable-gui --plain --config "$out/renode.config" \
    "$out/run.resc" </dev/null >"$out/renode.log" 2>&1
mapfile -t faults < <(tr -d '\r' < "$out/renode.log" | sed -n 's/^\(0x[0-9A-Fa-f]\{8\}\)$/\1/p')
[[ "${faults[*]}" == "0x00000000 0x00000000" ]] || { echo "Unexpected fault status. See $out/renode.log"; exit 1; }
python3 tools/check-tonbandgeraet.py extract "$out" "$greeting"
"$cli" --Werror dump --mode "$mode" "$out/trace.bin" >"$out/events.jsonl" 2>"$out/decode.log"
python3 tools/check-tonbandgeraet.py verify "$out" "$mode"
"$cli" --Werror conv --mode "$mode" --output "$out/uni.perfetto-trace" "$out/trace.bin" >"$out/conversion.log" 2>&1
test -s "$out/uni.perfetto-trace"
printf 'Timing artifacts %s\n' "$out"
