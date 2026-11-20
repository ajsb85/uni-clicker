#!/usr/bin/env python3
"""Drive the SEGGER RTT control block of the SystemView demo in Renode."""

import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def symbols(elf):
    output = subprocess.check_output(["arm-none-eabi-nm", "-S", elf], text=True)
    return {name: (int(address, 16), int(size, 16))
            for address, size, _, name in (line.split() for line in output.splitlines()
                                          if len(line.split()) == 4)}


def main():
    elf, directory = (Path(argument).resolve() for argument in sys.argv[1:])
    directory.mkdir(parents=True, exist_ok=True)
    table = symbols(elf)
    cb, cb_size = table["_SEGGER_RTT"]
    down, down_size = table["_DownBuffer"]
    header_size = 24
    descriptor = struct.Struct("<6I")
    require(cb_size == header_size + 4 * descriptor.size and down_size >= 2,
            "Unexpected Cortex-M RTT control block layout")
    # The host owns WrOff for each down buffer. Channel 1 is the fourth descriptor.
    down_write = cb + header_size + 3 * descriptor.size + 12
    root = Path(__file__).resolve().parent.parent
    uart = directory / "uart.txt"
    script = [
        'mach create "uni-systemview"',
        f"machine LoadPlatformDescription {json.dumps(str(root / 'sim/uni-clicker.repl'))}",
        f"sysbus LoadELF {json.dumps(str(elf))}",
        "cpu VectorTableOffset 0x08000000",
        f"usart6 CreateFileBackend {json.dumps(str(uart))}",
        'emulation RunFor "0.05"',
        f"sysbus WriteByte {down:#x} 1",
        f"sysbus WriteDoubleWord {down_write:#x} 1",
        'emulation RunFor "0.9"',
        f"sysbus WriteByte {down + 1:#x} 2",
        f"sysbus WriteDoubleWord {down_write:#x} 2",
        'emulation RunFor "0.02"',
        "sysbus ReadDoubleWord 0x40020c14",
        "sysbus ReadDoubleWord 0xe000ed28",
        "sysbus ReadDoubleWord 0xe000ed2c",
    ]
    for name, symbol in [("control", "_SEGGER_RTT"), ("sysview", "_UpBuffer"), ("terminal", "_acUpBuffer")]:
        address, size = table[symbol]
        script.append(f"dump_file {address:#x} {size} {json.dumps(str(directory / (name + '.bin')))}")
    script.append("quit")
    resc = directory / "run.resc"
    resc.write_text("\n".join(script) + "\n")
    logfile = directory / "renode.log"
    with logfile.open("w") as log:
        subprocess.run([os.environ.get("RENODE", "renode"), "--console", "--disable-gui", "--plain",
                        "--config", directory / "renode.config", resc],
                       stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=40, check=True)
    samples = re.findall(r"^0x([0-9a-fA-F]{8})$", logfile.read_text(), re.MULTILINE)
    require([int(sample, 16) for sample in samples] == [0x80, 0, 0], f"Unexpected PD7 or fault state. See {logfile}.")
    require(uart.is_file() and uart.read_bytes() == b"Hello, UNI Clicker from SystemView!\r\n",
            "Incorrect USART6 greeting")

    control = (directory / "control.bin").read_bytes()
    require(control[:16].rstrip(b"\x00") == b"SEGGER RTT", "Missing SEGGER RTT control block ID")
    require(struct.unpack_from("<2I", control, 16) == (2, 2), "Wrong RTT channel count")
    for channel, name, symbol, output in [(0, "terminal", "_acUpBuffer", "terminal.txt"),
                                          (1, "sysview", "_UpBuffer", "trace.bin")]:
        _, address, size, write, read, _ = descriptor.unpack_from(control, header_size + channel * descriptor.size)
        require((address, size) == table[symbol] and read == 0 and 0 < write < size,
                f"Invalid or wrapped RTT ring on channel {channel}")
        data = (directory / (name + ".bin")).read_bytes()[:write]
        (directory / output).write_bytes(data)
    require((directory / "terminal.txt").read_bytes() == b"UNI Clicker RTT ready\n",
            "Incorrect RTT terminal output")
    require(descriptor.unpack_from(control, header_size + 3 * descriptor.size)[3:5] == (2, 2),
            "Target did not consume the RTT start and stop commands")


if __name__ == "__main__":
    main()
