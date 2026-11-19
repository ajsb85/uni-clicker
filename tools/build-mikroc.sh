#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=${MIKROC_ARM_ROOT:?Source tools/bench-env.sh or set MIKROC_ARM_ROOT}
stage=${UNI_WINDOWS_ROOT:?Set UNI_WINDOWS_ROOT}/.uni-clicker-lab-cache/mikroc
mkdir -p "$stage" build/mikroc
work=$(mktemp -d "$stage/run.XXXXXX")
win_work=$(wslpath -w "$work")
for input in hello.c hello.mcpar; do
    sed 's/\r$//;s/$/\r/' "examples/mikroc/$input" > "$work/$input"
done
cp tools/build-mikroc.ps1 "$work/compile.ps1"
if ! (cd "$work" && timeout 60s powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File compile.ps1 -CompilerRoot "$(wslpath -w "$root")" -ProjectRoot "$win_work") \
    > "$work/compiler.log" 2>&1; then
    cat "$work/compiler.log" >&2
    printf 'mikroC compiler run %s\n' "$work" >&2
    exit 1
fi
for artifact in hello.hex hello.bin hello.lst hello.dbg hello.asm; do
    if [[ ! -s "$work/$artifact" ]]; then
        cat "$work/compiler.log" >&2
        printf 'mikroC emitted no %s. Compiler run %s\n' "$artifact" "$work" >&2
        exit 1
    fi
done

if ! python3 tools/mikroc-debug-elf.py "$work"; then
    printf 'Unable to package the native output. Compiler run %s\n' "$work" >&2
    exit 1
fi
exec 9>build/mikroc/.publish.lock
flock 9
cp "$work"/hello.{hex,bin,elf,lst,dbg,asm} "$work/compiler.log" build/mikroc/
printf 'Native mikroC build and listing-derived debug ELF in build/mikroc\n'
