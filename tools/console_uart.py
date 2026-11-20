#!/usr/bin/env python3
"""Run the console protocol over Windows COM or a local terminal."""

import argparse
import base64
import json
import os
from pathlib import Path
import re
import select
import subprocess
import time
import tty

from console_scenario import BURST, PONG, READY, SINGLES


class WindowsSerial:
    def __init__(self, port, dtr=False):
        helper = subprocess.check_output(
            ["wslpath", "-w", Path(__file__).resolve().with_name("console-serial.ps1")], text=True
        ).strip()
        command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                   "-File", helper, "-Port", port]
        if dtr:
            command.append("-Dtr")
        self.process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0,
        )
        try:
            if self.response(8) != b"OK":
                raise RuntimeError(f"Could not open {port}")
        except BaseException:
            self.close()
            raise

    def response(self, timeout):
        if not select.select([self.process.stdout], [], [], timeout)[0]:
            raise RuntimeError("Windows serial helper stopped responding")
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError("Windows serial helper exited")
        return line.rstrip(b"\r\n")

    def read(self):
        self.process.stdin.write(b"R\n")
        return base64.b64decode(self.response(3), validate=True)

    def write(self, data):
        self.process.stdin.write(b"W " + base64.b64encode(data) + b"\n")
        if self.response(3) != b"OK":
            raise RuntimeError("Windows serial write failed")

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stdout.close()


class LocalTerminal:
    def __init__(self, path):
        self.fd = os.open(path, os.O_NOCTTY | os.O_RDWR)
        try:
            tty.setraw(self.fd)
        except OSError:
            os.close(self.fd)
            raise

    def read(self):
        return os.read(self.fd, 256) if select.select([self.fd], [], [], 0.1)[0] else b""

    def write(self, data):
        pending = memoryview(data)
        while pending:
            pending = pending[os.write(self.fd, pending):]

    def close(self):
        os.close(self.fd)


def exercise(channel, output, traced, usb_cdc=False):
    pending = bytearray()
    with (output / "uart.txt").open("wb") as received, (output / "uart.jsonl").open("w") as transcript:
        def record(direction, data):
            transcript.write(json.dumps({"direction": direction, "hex": data.hex()}) + "\n")
            transcript.flush()

        def send(data):
            record("tx", data)
            channel.write(data)

        def line(timeout=2):
            deadline = time.monotonic() + timeout
            while b"\n" not in pending and time.monotonic() < deadline:
                chunk = channel.read()
                if chunk:
                    received.write(chunk)
                    received.flush()
                    record("rx", chunk)
                    pending.extend(chunk)
                    if len(pending) > 2048:
                        raise RuntimeError("USART6 response exceeds the receive limit")
            end = pending.find(b"\n") + 1
            reply = bytes(pending[:end])
            del pending[:end]
            return reply

        def expect(expected, timeout=2):
            reply = line(timeout)
            if reply != expected or (not expected and pending):
                raise RuntimeError(f"Expected {expected!r}, received {reply or bytes(pending)!r}")

        if usb_cdc:
            for command, reply in [(b"ping\n", b"OK USB pong\r\n"),
                                   (b"led on\r\n", b"OK led on\r\n"),
                                   (b"led off\n", b"OK led off\r\n"),
                                   (b"invalid\n", b"ERR command\r\n")]:
                send(command)
                expect(reply)
            print("USB CDC command round trip passed.")
            return

        expect(READY, 4)
        for command, reply in SINGLES:
            send(command)
            expect(reply, 2 if reply else 0.15)
        send(b"ping\n" * BURST)
        burst_replies = 0
        while reply := line(0.3):
            if reply != PONG or burst_replies == BURST:
                raise RuntimeError(f"Unexpected burst reply {reply!r}")
            burst_replies += 1
        if pending or not burst_replies:
            raise RuntimeError("Incomplete or missing burst response")
        send(b"status\n")
        status = re.fullmatch(rb"OK led=off dropped=(\d+) errors=(\d+)\r\n", line())
        if status is None:
            raise RuntimeError("Invalid USART6 status after the burst")
        dropped, errors = map(int, status.groups())
        if dropped + burst_replies != BURST or errors:
            raise RuntimeError(f"Burst accounting failed: {burst_replies} replies, {dropped} dropped, {errors} errors")
        send(b"ping\n")
        expect(PONG)
        if traced:
            send(b"trace\n")
            expect(b"OK trace\r\n")
    (output / "console.json").write_text(
        json.dumps({"burst_replies": burst_replies, "dropped": dropped, "errors": errors}) + "\n")
    print(f"USART6 protocol and recovery passed. Burst produced {burst_replies} replies and {dropped} queue drops.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    transport = parser.add_mutually_exclusive_group(required=True)
    transport.add_argument("--port", type=str.upper)
    transport.add_argument("--tty", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--usb-cdc", action="store_true")
    parser.add_argument("reset", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.port and not re.fullmatch(r"COM[1-9]\d*", args.port, flags=re.ASCII):
        parser.error("--port must be a Windows COM port, such as COM7")
    if args.usb_cdc and (not args.port or args.trace or args.reset):
        parser.error("--usb-cdc requires a Windows COM port and runs against an already booted device")
    args.output.mkdir(parents=True, exist_ok=True)
    channel = WindowsSerial(args.port, dtr=args.usb_cdc) if args.port else LocalTerminal(args.tty)
    try:
        if args.reset:
            subprocess.run(args.reset[1:] if args.reset[0] == "--" else args.reset, timeout=15, check=True)
        exercise(channel, args.output, args.trace, args.usb_cdc)
    finally:
        channel.close()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from None
