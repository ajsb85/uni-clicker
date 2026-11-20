#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/bench-env.sh
if [[ $# -lt 2 || ! "$1" =~ ^(stm32cube|freertos|freertos-console)$ ||
      ( $# != 2 && ( "$3" != --hardware ||
        ( "$1" == freertos-console && ( $# != 5 || ! "${4^^}" =~ ^COM[1-9][0-9]*$ || ! "$5" =~ ^([1-9]|10)$ ) ) ||
        ( "$1" != freertos-console && $# != 3 ) ) ) ]]; then
    echo 'Usage: tools/check-tonbandgeraet.sh PROFILE OUTPUT [--hardware [COMx RUNS for freertos-console]]' >&2
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
"$cli" --version >"$out/converter-version.txt"
if revision=$(git -C "$tonband" rev-parse --verify HEAD 2>/dev/null); then
    printf '%s\n' "$revision" >"$out/recorder-revision.txt"
fi

sdk="${STM32CUBE_F7:-$PWD/.cache/vendor/STM32CubeF7}"
case "$profile" in
    stm32cube)
        make tband-stm32cube TRACE_BUILD_DIR="$out" STM32CUBE_F7="$sdk" TONBAND_ROOT="$tonband" >"$out/build.log" 2>&1
        mode=bare-metal
        greeting=STM32Cube
        ;;
    freertos|freertos-console)
        {
            cmake -S examples/frameworks -B "$out" -G Ninja \
                -DCMAKE_TOOLCHAIN_FILE="$PWD/examples/necto/arm-gcc.cmake" \
                -DSTM32CUBE_F7="$sdk" -DFRAMEWORK="$profile" -DKERNEL_DIR="$FREERTOS_ROOT" \
                -DTONBAND_ROOT="$tonband"
            cmake --build "$out"
        } >"$out/build.log" 2>&1
        mode=free-rtos
        greeting=FreeRTOS
        ;;
esac

elf="$out/hello.elf"
convert() {
    local destination=$1 expected_greeting=$2 verification_profile=$3
    python3 tools/check-tonbandgeraet.py extract "$destination" "$expected_greeting"
    "$cli" --Werror dump --mode "$mode" "$destination/trace.bin" >"$destination/events.jsonl" 2>"$destination/decode.log"
    python3 tools/check-tonbandgeraet.py verify "$destination" "$verification_profile"
    "$cli" --Werror conv --mode "$mode" --output "$destination/uni.perfetto-trace" \
        "$destination/trace.bin" >"$destination/conversion.log" 2>&1
    test -s "$destination/uni.perfetto-trace"
}

if [[ $# == 5 ]]; then
    ports=$(timeout --kill-after=1s 6s powershell.exe -NoProfile -NonInteractive \
        -Command '[System.IO.Ports.SerialPort]::GetPortNames()')
    if ! tr -d '\r' <<< "$ports" | rg -qix -- "$4"; then
        echo "Windows does not enumerate $4. Connect the USART6 adapter and select its COM port." >&2
        exit 1
    fi
    for ((i=1; i<=$5; i++)); do
        session="$out/run-$i"
        mkdir "$session"
        "${UNI_TRACE_CLI:-build/cli/debug/uni-cli}" capture-trace --hardware "$elf" "$session" --uart "$4"
        convert "$session" '' freertos-console-hardware
    done
    python3 tools/check-tonbandgeraet.py baseline "$out" "$5"
    printf 'Physical USART6 timing artifacts %s\n' "$out"
    exit 0
fi

if [[ ${3:-} == --hardware ]]; then
    "${UNI_TRACE_CLI:-build/cli/debug/uni-cli}" capture-trace --hardware "$elf" "$out"
    greeting=
elif [[ "$profile" == freertos-console ]]; then
    python3 tools/simulate-console.py "$elf" "$out" --trace
    greeting=
else
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
fi
convert "$out" "$greeting" "$profile"
if [[ "$profile" == freertos-console ]]; then
    python3 tools/simulate-console-live.py "$elf" "$out/live/run-1"
    convert "$out/live/run-1" '' freertos-console-uart
    python3 tools/check-tonbandgeraet.py baseline "$out/live" 1
fi
printf 'Timing artifacts %s\n' "$out"
