#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=${MIKROC_ARM_ROOT:?Source tools/bench-env.sh or set MIKROC_ARM_ROOT}
stage=${UNI_WINDOWS_ROOT:?Set UNI_WINDOWS_ROOT}/.uni-clicker-lab-cache/mikroc
mkdir -p "$stage" build/mikroc
work=$(mktemp -d "$stage/run.XXXXXX")
win_work=$(wslpath -w "$work")
win_compiler=$(wslpath -w "$root")
for input in hello.c hello.mcpar; do
    sed 's/$/\r/' "examples/mikroc/$input" > "$work/$input"
done
sed 's/$/\r/' > "$work/compile.cmd" <<SCRIPT
@echo off
cd /d "$win_work"
"$win_compiler\mikroCARM.exe" -MSF -DBG -pSTM32F746ZG -Y -O11111110 -fo16 -BIN -N"$win_work\hello.mcpar" -SP"$win_compiler\Defs" -SP"$win_compiler\Uses" -SP"$win_work" "$win_work\hello.c"
SCRIPT
(cd "$work" && timeout 60s cmd.exe /d /c compile.cmd) > "$work/compiler.log" 2>&1
cp "$work/compiler.log" build/mikroc/compiler.log
if [[ ! -s "$work/hello.hex" ]]; then
    cat build/mikroc/compiler.log >&2
    echo "mikroC emitted no HEX image. Compiler run: $work" >&2
    exit 1
fi
cp "$work/hello.hex" build/mikroc/hello.hex
arm-none-eabi-objcopy -I ihex -O binary build/mikroc/hello.hex build/mikroc/hello.bin
