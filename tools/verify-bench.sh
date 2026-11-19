#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -eq 0 ]]; then
    echo 'Usage: tools/verify-bench.sh <profile> [profile ...]' >&2
    exit 2
fi

source tools/bench-env.sh
make cli
cli=build/cli/debug/uni-cli
mkdir -p .cache/verification
run=$(mktemp -d "$PWD/.cache/verification/bench.XXXXXX")
exec 9>.cache/probe.lock
flock -n 9 || { echo 'Another bench run owns the probe.' >&2; exit 1; }
port=${UNI_GDB_PORT:-3333}
endpoint="127.0.0.1:$port"
server=
stop_server() {
    if [[ -n "$server" ]]; then
        timeout 6s "${GDB:-gdb-multiarch}" -q -nx -batch -ex 'set remotetimeout 2' \
            -ex "target extended-remote $endpoint" -ex 'monitor resume' \
            -ex 'monitor shutdown' >"$run/shutdown.log" 2>&1 || true
        if kill -0 "$server" 2>/dev/null; then
            kill "$server" 2>/dev/null || true
        fi
        wait "$server" 2>/dev/null || true
        server=
    fi
}
trap stop_server EXIT

for image; do
    "$cli" analyze "$image" >"$run/$image-elf.txt"
    "$cli" flash "$image" >"$run/$image-flash.txt"
    debug/start-openocd.sh >"$run/$image-openocd.txt" 2>&1 &
    server=$!
    ready=false
    for attempt in {1..50}; do
        kill -0 "$server" 2>/dev/null || break
        if grep -Fq "Listening on port $port for gdb" "$run/$image-openocd.txt"; then
            ready=true
            break
        fi
        sleep 0.1
    done
    if [[ "$ready" != true ]]; then
        cat "$run/$image-openocd.txt" >&2
        exit 1
    fi
    printf 'Verifying %s\n' "$image"
    "$cli" verify "$image" "$endpoint" 2>&1 | tee "$run/$image-gdb.txt"
    stop_server
done
printf 'Bench logs %s\n' "$run"
