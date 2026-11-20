#!/usr/bin/env python3
"""Exercise the FreeRTOS USART6 console in Renode."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def quote(path):
    return json.dumps(str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args()
    if not args.elf.is_file():
        parser.error(f"firmware ELF does not exist: {args.elf}")
    directory = args.directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    uart = directory / "uart.txt"
    expected = ["READY 115200 8N1"]
    script = [
        'mach create "uni-console"',
        f"machine LoadPlatformDescription {quote(ROOT / 'sim/uni-clicker.repl')}",
        f"sysbus LoadELF {quote(args.elf.resolve())}",
        "cpu VectorTableOffset 0x08000000",
        f"usart6 CreateFileBackend {quote(uart)}",
        'emulation RunFor "0.05"',
    ]

    def send(data, *responses):
        script.extend(f"usart6 WriteChar 0x{byte:02x}" for byte in data)
        script.append('emulation RunFor "0.02"')
        expected.extend(responses)

    send(b"pi")
    send(b"ng\n", "OK pong")
    send(b"led on\r\n", "OK led on")
    script.append("sysbus ReadDoubleWord 0x40020c14")
    send(b"status\n", "OK led=on dropped=0 errors=0")
    send(b"wat\n", "ERR unknown")
    send(b"pi\rng\n", "ERR malformed")
    send(b"ping\x00\n", "ERR malformed")
    send(b"a" * 24 + b"\n", "ERR malformed")
    send(b"\n", "ERR malformed")
    send(b"led off\n", "OK led off")
    script.append("sysbus ReadDoubleWord 0x40020c14")
    send(b"ping\n" * 10, *(["OK pong"] * 4))
    send(b"status\n", "OK led=off dropped=6 errors=0")
    send(b"ping\n", "OK pong")
    if args.trace:
        send(b"trace\n", "OK trace")
        symbols = subprocess.check_output(["arm-none-eabi-nm", "-S", args.elf], text=True)
        snapshot = next(fields for line in symbols.splitlines()
                        if (fields := line.split())[-1] == "uni_trace_capture")
        script.append(f"dump_file 0x{snapshot[0]} {int(snapshot[1], 16)} {quote(directory / 'sram.bin')}")
    script += ["sysbus ReadDoubleWord 0xE000ED28", "sysbus ReadDoubleWord 0xE000ED2C", "quit"]

    resc = directory / "run.resc"
    resc.write_text("\n".join(script) + "\n")
    expected_bytes = ("\r\n".join(expected) + "\r\n").encode()
    (directory / "expected.txt").write_bytes(expected_bytes)
    log = directory / "renode.log"
    with log.open("w") as output:
        subprocess.run([os.environ.get("RENODE", "renode"), "--console", "--disable-gui", "--plain",
                        "--config", directory / "renode.config", resc],
                       stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                       timeout=40, check=True)
    if not uart.is_file() or uart.read_bytes() != expected_bytes:
        raise SystemExit(f"USART6 transcript differs. Compare {uart} and {directory / 'expected.txt'}.")
    responses = re.findall(r"^0x([0-9a-fA-F]{8})$", log.read_text(), re.MULTILINE)
    if [int(value, 16) for value in responses] != [0x80, 0, 0, 0]:
        raise SystemExit(f"Unexpected PD7 and fault register samples {responses}. See {log}.")
    print("USART6 commands, PD7, malformed input, four queued commands, six drops, and recovery verified.")
    print(f"Renode artifacts {directory}")


if __name__ == "__main__":
    main()
