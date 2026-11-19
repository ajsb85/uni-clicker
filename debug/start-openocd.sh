#!/usr/bin/env bash
set -euo pipefail

openocd=${OPENOCD:-openocd}
port=${UNI_GDB_PORT:-3333}
if [[ ! "$port" =~ ^[0-9]+$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
    echo "Invalid UNI_GDB_PORT" >&2
    exit 2
fi
scripts=()
if [[ -n "${OPENOCD_SCRIPTS:-}" ]]; then
    directory=$OPENOCD_SCRIPTS
    if [[ "$openocd" == *.exe ]]; then
        directory=$(wslpath -w "$directory")
    fi
    scripts=(-s "$directory")
fi
exec "$openocd" "${scripts[@]}" -f interface/stlink.cfg -f target/stm32f7x.cfg \
    -c "bindto 127.0.0.1; gdb port $port; tcl port disabled; telnet port disabled; adapter speed 240; init"
