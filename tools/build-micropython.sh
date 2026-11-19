#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk=${MICRO_PYTHON_ROOT:?Set MICRO_PYTHON_ROOT or source tools/bench-env.sh}
out="$PWD/build/micropython"
mkdir -p "$out" .cache
board="$out/boards/UNI_CLICKER_F746ZG"
python3 examples/frameworks/micropython/stage-board.py "$sdk" "$board" --freeze-hello

host_flags=()
if ${CC:-cc} -Q --help=warnings | grep 'unterminated-string-initialization' >/dev/null; then
    host_flags=(CFLAGS_EXTRA=-Wno-error=unterminated-string-initialization)
fi
make -C "$sdk/mpy-cross" BUILD="$out/mpy-cross" "${host_flags[@]}" -j"${UNI_JOBS:-4}"
make -C "$sdk/ports/stm32" BOARD=UNI_CLICKER_F746ZG BOARD_DIR="$board" \
    BUILD="$out/firmware" MICROPY_MPYCROSS="$out/mpy-cross/mpy-cross" -j"${UNI_JOBS:-4}"
