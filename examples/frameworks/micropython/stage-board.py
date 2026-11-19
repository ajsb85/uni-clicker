"""Copy the upstream STM32F746ZG board and remap USART6 for the UNI Clicker."""

import argparse
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("micropython", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    source = args.micropython / "ports" / "stm32" / "boards" / "NUCLEO_F746ZG"
    shutil.copytree(source, args.destination)
    config = args.destination / "mpconfigboard.h"
    text = config.read_text()
    for old, new in (
        ("(pin_G14)", "(pin_C6)"),
        ("(pin_G9)", "(pin_C7)"),
    ):
        if text.count(old) != 1:
            raise SystemExit(f"Unexpected board pin definition for {old}")
        text = text.replace(old, new)
    config.write_text(text)


if __name__ == "__main__":
    main()
