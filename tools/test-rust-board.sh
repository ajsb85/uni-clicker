#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/bench-env.sh

mkdir -p .cache/verification
out=$(mktemp -d "$PWD/.cache/verification/rust-board.XXXXXX")
printf 'Board test logs %s\n' "$out"
cargo test --locked --release --no-run --target thumbv7em-none-eabihf \
    --test board --manifest-path examples/rust/Cargo.toml \
    --target-dir "${RUST_BUILD_DIR:-$PWD/build/rust/cargo}" --message-format=json \
    >"$out/build.jsonl" 2>"$out/build.log"
elf=$(python3 - "$out/build.jsonl" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    executables = [
        item["executable"]
        for line in stream
        if (item := json.loads(line))["reason"] == "compiler-artifact"
        and item["target"]["name"] == "board"
        and item["executable"]
    ]
if len(executables) != 1:
    raise SystemExit("expected exactly one board test ELF")
print(executables[0])
PY
)

exec 9>.cache/probe.lock
flock -n 9 || { echo 'Another bench run owns the probe.' >&2; exit 1; }
probe="0483:3748${UNI_PROBE_SERIAL:+:$UNI_PROBE_SERIAL}"
if [[ "$PROBE_RS" == *.exe ]]; then
    elf=$(wslpath -w "$elf")
fi
timeout --kill-after=3s 80s "$PROBE_RS" run --chip STM32F746ZG --protocol swd \
    --probe "$probe" --speed 240 --non-interactive --connect-under-reset \
    --preverify --verify --disable-progressbars "$elf" 2>&1 | tee "$out/tests.log"
