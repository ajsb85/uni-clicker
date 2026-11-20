#!/usr/bin/env bash
set -euo pipefail

# STM32Tools invokes this name on Linux. Forward its SWD recipe to Windows.
programmer="${CUBE_PROG:?Source tools/bench-env.sh or set CUBE_PROG}"
args=()
while (( $# )); do
    case "$1" in
        --download)
            args+=(--download "$(wslpath -w "$2")" "$3" --verify)
            shift 3
            ;;
        "port=SWD "*)
            read -r -a connection <<< "$1"
            args+=("${connection[@]}")
            shift
            ;;
        "")
            shift
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done
exec "$programmer" "${args[@]}"
