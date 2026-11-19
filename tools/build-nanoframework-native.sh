#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

cache="$PWD/.cache/sdk-native"
runtime_rev=e903edbe5258e8c6887c91c448ea5a0305e7040f
community_rev=21b7f0bbe310e8c1487bcca41bfa6a7ee730fac0
runtime="${NANO_SOURCE:-$cache/nano-e903edb}"
community="${NANO_COMMUNITY:-$cache/nano-community}"
chibios="${NANO_CHIBIOS:-$cache/work/nano-f746/_deps/chibios-src}"
mbedtls="${NANO_MBEDTLS:-$cache/work/nano-posix-v2/_deps/mbedtls-src}"
native_build="${NANO_NATIVE_BUILD_DIR:-$cache/work/nanoframework-native}"
python="${FRAMEWORK_PYTHON:-$PWD/.cache/framework-venv/bin/python}"
source_board=ChibiOS/ST_NUCLEO144_F746ZG
target=targets-community/ChibiOS/UNI_CLICKER_F746ZG
example="$PWD/examples/frameworks/nanoframework"
out="$PWD/build/nanoframework"

if [[ ! -f "$runtime/CMakeLists.txt" && -z "${NANO_SOURCE:-}" ]]; then
    archive="${UNI_WINDOWS_ROOT:?Source tools/bench-env.sh first}/.uni-clicker-lab-cache/frameworks/nf-interpreter-e903edb.tar.gz"
    if [[ -f "$archive" ]]; then
        mkdir -p "$runtime"
        tar -xzf "$archive" --strip-components=1 -C "$runtime"
    fi
fi
if [[ ! -f "$runtime/CMakeLists.txt" || ! -d "$chibios/os" || ! -f "$mbedtls/CMakeLists.txt" ]]; then
    echo "Provide the local nanoCLR $runtime_rev, ChibiOS and Mbed TLS sources. See docs/frameworks.md." >&2
    exit 1
fi
"$python" -c 'import kconfiglib'
if ! git -C "$community" cat-file -e "$community_rev:$source_board/defconfig"; then
    echo "Provide the local nf-Community-Targets revision $community_rev via NANO_COMMUNITY." >&2
    exit 1
fi

board="$runtime/$target"
port_hash=$(cat "$example/native-board.patch" "$example/native-board.c" | sha256sum | cut -d ' ' -f1)
stamp="$board/.uni-board-revision"
if [[ ! -f "$board/defconfig" || ! -f "$stamp" || $(cat "$stamp") != "$community_rev $port_hash" ]]; then
    mkdir -p "$board"
    git -C "$community" archive "$community_rev:$source_board" | tar -xf - -C "$board"
    # The upstream files use CRLF. Normalize only the files touched by the patch.
    mapfile -t patch_files < <(sed -n 's|^--- a/||p' "$example/native-board.patch")
    for name in "${patch_files[@]}"; do
        sed -i 's/\r$//' "$board/$name"
    done
    patch --batch --fuzz=0 -p1 -d "$board" < "$example/native-board.patch"
    cp "$example/native-board.c" "$board/board.c"
    sed -i 's/CONFIG_TARGET_BOARD="ST_NUCLEO144_F746ZG"/CONFIG_TARGET_BOARD="UNI_CLICKER_F746ZG"/' "$board/defconfig"
    printf '%s %s\n' "$community_rev" "$port_hash" > "$stamp"
fi

export PATH="$(dirname "$python"):$PATH"
cmake -S "$runtime" -B "$native_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$runtime/CMake/toolchain.arm-none-eabi.cmake" \
    -DNF_TARGET_DEFCONFIG="$target/defconfig" \
    -DPython3_EXECUTABLE="$python" \
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
    -DFETCHCONTENT_SOURCE_DIR_CHIBIOS="$chibios" \
    -DFETCHCONTENT_SOURCE_DIR_MBEDTLS="$mbedtls" \
    -DMBEDTLS_SOURCE="$mbedtls"
cmake --build "$native_build" --parallel "${NANO_JOBS:-8}"
python3 tools/package-nanoframework.py "$native_build" "$out"
cp "$native_build"/{nanoBooter,nanoCLR}.elf "$out/"
