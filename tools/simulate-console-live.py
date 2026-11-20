#!/usr/bin/env python3
"""Run the console UART host protocol against live Renode firmware."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

from console_uart import LocalTerminal, exercise

elf, output = (Path(value).resolve() for value in sys.argv[1:])
output.mkdir(parents=True, exist_ok=False)
terminal = output / "uart.pty"
platform = Path(__file__).resolve().parents[1] / "sim/uni-clicker.repl"
symbols = subprocess.check_output(["arm-none-eabi-nm", "-S", elf], text=True)
address, size, *_ = next(row.split() for row in symbols.splitlines()
                         if row.endswith(" uni_trace_capture"))
setup = output / "run.resc"
setup.write_text("\n".join([
    'mach create "uni-console-live"',
    f"machine LoadPlatformDescription {json.dumps(str(platform))}",
    f"sysbus LoadELF {json.dumps(str(elf))}",
    "cpu VectorTableOffset 0x08000000",
    f'emulation CreateUartPtyTerminal "uniconsole" {json.dumps(str(terminal))}',
    "connector Connect sysbus.usart6 uniconsole",
]) + "\n")
logfile = output / "renode.log"
with logfile.open("w") as log:
    simulation = subprocess.Popen(
        [os.environ.get("RENODE", "renode"), "--console", "--disable-gui", "--plain",
         "--config", output / "renode.config", setup],
        stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, text=True
    )
    channel = None
    try:
        deadline = time.monotonic() + 15
        while channel is None:
            try:
                channel = LocalTerminal(terminal)
            except FileNotFoundError:
                if simulation.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError(f"Renode UART endpoint unavailable. See {logfile}.") from None
                time.sleep(0.05)

        simulation.stdin.write("start\n")
        simulation.stdin.flush()
        exercise(channel, output, traced=True)
        script = "\n".join([
            "pause",
            "sysbus ReadDoubleWord 0x40020c14",
            "sysbus ReadDoubleWord 0xe000ed28",
            "sysbus ReadDoubleWord 0xe000ed2c",
            f"dump_file 0x{address} {int(size, 16)} {json.dumps(str(output / 'sram.bin'))}",
            "quit",
        ]) + "\n"
        (output / "finish.resc").write_text(script)
        simulation.communicate(script, timeout=15)
        if simulation.returncode:
            raise RuntimeError(f"Renode returned {simulation.returncode}. See {logfile}.")
    finally:
        if channel is not None:
            channel.close()
        if simulation.poll() is None:
            simulation.kill()
        simulation.wait()
        terminal.unlink(missing_ok=True)

samples = re.findall(r"(?:^|> )0x([0-9a-fA-F]{8})$", logfile.read_text(), re.MULTILINE)
if samples != ["00000000"] * 3:
    raise SystemExit(f"Unexpected PD7 or Cortex-M fault state. See {logfile}.")
