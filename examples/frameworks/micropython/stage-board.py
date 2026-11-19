"""Stage the MicroPython STM32 port for the UNI Clicker."""

import argparse
import shutil
from pathlib import Path


def write_if_changed(path, content):
    if not path.exists() or path.read_text() != content:
        path.write_text(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("micropython", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--freeze-hello", action="store_true")
    args = parser.parse_args()

    source = args.micropython / "ports" / "stm32" / "boards" / "NUCLEO_F746ZG"
    if source.resolve() == args.destination.resolve():
        raise SystemExit("Choose a separate staging directory")
    if not args.destination.exists():
        shutil.copytree(source, args.destination)
    config = args.destination / "mpconfigboard.h"
    text = (source / config.name).read_text()
    for old, new in (
        ("(pin_G14)", "(pin_C6)"),
        ("(pin_G9)", "(pin_C7)"),
        ('"NUCLEO-F746ZG"', '"UNI Clicker F746ZG"'),
        ("#define MICROPY_HW_CLK_PLLM (4)", "#define MICROPY_HW_CLK_PLLM (8)"),
        ("#define MICROPY_HW_UART_REPL        PYB_UART_3", "#define MICROPY_HW_UART_REPL        PYB_UART_6"),
        ("#define MICROPY_HW_LED1             (pin_B0)", "#define MICROPY_HW_LED1             (pin_D7)"),
    ):
        if text.count(old) != 1:
            raise SystemExit(f"Unexpected board pin definition for {old}")
        text = text.replace(old, new)
    text += "\n#define MICROPY_HW_CLK_USE_HSI (1)\n"
    make_config = args.destination / "mpconfigboard.mk"
    text_make = (source / make_config.name).read_text()
    manifest = args.destination / "manifest.py"
    manifest_text = (source / manifest.name).read_text()
    if args.freeze_hello:
        unused = ("#define MICROPY_HW_ETH_", "#define MICROPY_HW_LED2 ", "#define MICROPY_HW_LED3 ")
        text = "\n".join(line for line in text.splitlines() if not line.startswith(unused)) + "\n"
        text = text.replace("#define MICROPY_HW_HAS_SWITCH       (1)", "#define MICROPY_HW_HAS_SWITCH       (0)")
        text = text.replace("#define MICROPY_HW_ENABLE_USB       (1)", "#define MICROPY_HW_ENABLE_USB       (0)")
        text = text.replace("#define MICROPY_HW_HAS_FLASH        (1)", "#define MICROPY_HW_HAS_FLASH        (0)")
        text += '\n#define MICROPY_HW_ENABLE_INTERNAL_FLASH_STORAGE (0)\n'
        text += '#define MICROPY_BOARD_FROZEN_BOOT_FILE "uni_hello.py"\n'
        for option in ("MICROPY_PY_LWIP", "MICROPY_PY_SSL", "MICROPY_SSL_MBEDTLS"):
            text_make = text_make.replace(f"{option} = 1", f"{option} = 0")
        write_if_changed(args.destination / "uni_hello.py", Path(__file__).with_name("main.py").read_text())
        manifest_text = 'freeze(".", "uni_hello.py")\n'
    write_if_changed(config, text)
    write_if_changed(make_config, text_make)
    write_if_changed(manifest, manifest_text)
    pins = args.destination / "pins.csv"
    pins_text = (source / pins.name).read_text()
    for old, new in (
        ("LED1,PB0", "LED1,PD7"),
        ("UART6_TX,PG14", "UART6_TX,PC6"),
        ("UART6_RX,PG9", "UART6_RX,PC7"),
    ):
        if pins_text.count(old) != 1:
            raise SystemExit(f"Unexpected board pin mapping for {old}")
        pins_text = pins_text.replace(old, new)
    write_if_changed(pins, pins_text)


if __name__ == "__main__":
    main()
