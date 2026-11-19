#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
case "${1:-}" in
    stm32cube) language=STM32Cube; artifact=hello.elf ;;
    arduino) language=Arduino; artifact=HelloUni.ino.elf ;;
    rust) language=Rust; artifact=hello.elf ;;
    swift) language='Embedded Swift'; artifact=hello.elf ;;
    *) echo 'Usage: tools/simulate.sh {stm32cube|arduino|rust|swift}' >&2; exit 2 ;;
esac

binary="$PWD/build/$1/$artifact"
if [[ ! -f "$binary" ]]; then
    echo "Run make $1 first." >&2
    exit 1
fi
export TMPDIR="$PWD/.cache/tmp"
mkdir -p "$TMPDIR" .cache/sim
run=$(mktemp -d "$PWD/.cache/sim/$1.XXXXXX")
cat > "$run/run.resc" <<SCRIPT
mach create "uni-clicker"
machine LoadPlatformDescription "$PWD/sim/uni-clicker.repl"
sysbus LoadELF "$binary"
usart6 CreateFileBackend "$run/uart.txt"
emulation RunFor "1.4"
quit
SCRIPT

if ! timeout --kill-after=2s 30s "${RENODE:-renode}" --console --disable-gui --plain \
    --config "$run/renode.config" "$run/run.resc" </dev/null >"$run/renode.log" 2>&1; then
    cat "$run/renode.log" >&2
    exit 1
fi

printf 'Hello, UNI Clicker from %s!\r\nHello, UNI Clicker from %s!\r\n' "$language" "$language" > "$run/expected.txt"
if ! cmp -s "$run/expected.txt" "$run/uart.txt"; then
    echo "Unexpected USART6 output. Inspect $run/uart.txt and $run/renode.log." >&2
    exit 1
fi
cat "$run/uart.txt"
