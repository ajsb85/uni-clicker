#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$#" -gt 1 || ! "${1:-smoke}" =~ ^(smoke|gdb)$ ]]; then
    echo 'Usage: tools/simulate-nanoframework.sh [smoke|gdb]' >&2
    exit 2
fi
mode=${1:-smoke}
out="$PWD/build/nanoframework"
image="$out/uni-clicker-nano.bin"
elf="$out/nanoCLR.elf"
if [[ ! -f "$image" || ! -f "$elf" ]]; then
    echo 'Run make nanoframework-native first.' >&2
    exit 1
fi

export TMPDIR="$PWD/.cache/tmp"
mkdir -p "$TMPDIR" .cache/sim
run=$(mktemp -d "$PWD/.cache/sim/nanoframework-native.$mode.XXXXXX")
cat > "$run/run.resc" <<SCRIPT
mach create "uni-clicker"
machine LoadPlatformDescription "$PWD/sim/uni-clicker.repl"
sysbus LoadBinary "$image" 0x08000000
cpu VectorTableOffset 0x08000000
usart6 CreateFileBackend "$run/wire-protocol.bin"
SCRIPT
if [[ "$mode" == gdb ]]; then
    printf 'machine StartGdbServer 3334\n' >> "$run/run.resc"
    printf 'GDB endpoint 127.0.0.1:3334\nUART output %s/wire-protocol.bin\n' "$run"
    exec "${RENODE:-renode}" --console --disable-gui --plain \
        --config "$run/config" "$run/run.resc"
fi

emit=$(arm-none-eabi-nm "$elf" | awk '$3 == "_ZN9CLR_Debug4EmitEPKci.part.0" {print "0x" $1}')
[[ "$emit" =~ ^0x[0-9a-fA-F]+$ ]] || { echo 'Could not locate the nanoCLR Emit symbol.' >&2; exit 1; }
greeting='Hello, UNI Clicker from .NET nanoFramework!'
cat >> "$run/run.resc" <<SCRIPT
cpu AddHook $emit "address = self.GetRegisterUnsafe(0).RawValue; actual = ''.join(chr(self.Bus.ReadByte(address + i)) for i in range(${#greeting} + 1)); self.InfoLog(actual[:-1]) if actual == '$greeting' + chr(0) else None"
emulation RunFor "6"
sysbus ReadDoubleWord 0xE000ED08
sysbus ReadDoubleWord 0xE000ED28
sysbus ReadDoubleWord 0xE000ED2C
quit
SCRIPT
if ! timeout --kill-after=2s 40s "${RENODE:-renode}" --console --disable-gui --plain \
    --config "$run/config" "$run/run.resc" </dev/null >"$run/renode.log" 2>&1; then
    echo "Renode did not complete. Inspect $run/renode.log." >&2
    exit 1
fi
mapfile -t registers < <(tr -d '\r' < "$run/renode.log" | sed -n 's/^\(0x[0-9A-Fa-f]\{8\}\)$/\1/p')
if [[ "${registers[*]}" != '0x00210000 0x00000000 0x00000000' ]] \
    || (( $(grep -Fc "$greeting" "$run/renode.log") < 2 )) \
    || ! grep -aqF NFPKTV1 "$run/wire-protocol.bin"; then
    echo "nanoCLR smoke check failed. Inspect $run/renode.log and $run/wire-protocol.bin." >&2
    exit 1
fi
grep -F "$greeting" "$run/renode.log"
printf 'nanoCLR VTOR 0x00210000, CFSR and HFSR clear. Logs in %s\n' "$run"
