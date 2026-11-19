#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
zig=${1:-zig}
mkdir -p .cache/tmp .cache/zig .cache/zig-local .cache/zig-packages
export TMPDIR="$PWD/.cache/tmp"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$PWD/.cache/zig}"
export ZIG_LOCAL_PKG_DIR="${ZIG_LOCAL_PKG_DIR:-$PWD/.cache/zig-packages}"
mkdir -p "$ZIG_LOCAL_PKG_DIR"
# Zig's host libc discovery on this Ubuntu system can omit the multiarch header directory.
if [[ -z "${ZIG_LIBC:-}" && "$(uname -s)" == Linux ]]; then
    target=$(cc -print-multiarch)
    multiarch="/usr/include/$target"
    if [[ -n "$target" && -d "$multiarch/asm" ]]; then
        libc="$PWD/.cache/zig-libc.txt"
        "$zig" libc | sed "s|^sys_include_dir=/usr/include$|sys_include_dir=$multiarch|" > "$libc"
        export ZIG_LIBC="$libc"
    fi
fi
exec "$zig" build --build-file examples/zig/build.zig --cache-dir "$PWD/.cache/zig-local" \
    --prefix "$PWD/build/zig/microzig" -Doptimize=ReleaseSmall -j4
