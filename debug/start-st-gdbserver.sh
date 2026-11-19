#!/usr/bin/env bash
set -euo pipefail
windows_root=${UNI_WINDOWS_ROOT:?Source tools/bench-env.sh or set UNI_WINDOWS_ROOT}
server=${ST_GDB_SERVER:-"$windows_root/NECTOStudio7/packages/st_tools/stlinkgdbserver/tools/bin/ST-LINK_gdbserver.exe"}
programmer=${CUBE_PROG:?Set CUBE_PROG to the Windows programmer}
scratch="$windows_root/.uni-clicker-lab-cache/st-gdb"
mkdir -p "$scratch"
exec "$server" -d -g -p 3335 --frequency 400 \
    -cp "$(wslpath -w "$(dirname "$programmer")")" --temp-path "$(wslpath -w "$scratch")"
