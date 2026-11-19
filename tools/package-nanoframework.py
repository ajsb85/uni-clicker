"""Pack nanoBooter, nanoCLR and the managed deployment for STM32F746ZG."""

import argparse
from pathlib import Path
import struct


FLASH_BASES = (0x08000000, 0x00200000)
FLASH_SIZE = 0x100000
CLR_OFFSET = 0x10000
DEPLOY_OFFSET = 0xC0000
CORLIB_CONTRACT = 0x532E6934


def load_firmware(path, offset, limit):
    data = path.read_bytes()
    if not 8 <= len(data) <= limit:
        raise ValueError(f"{path.name} has an unexpected size ({len(data)} bytes)")
    stack, reset = struct.unpack_from("<II", data)
    if not 0x20000004 <= stack <= 0x20050000 or stack % 4 or not reset & 1:
        raise ValueError(f"{path.name} has invalid vectors {stack:#x}, {reset:#x}")
    pc = reset & ~1
    if not any(base + offset <= pc < base + offset + len(data) for base in FLASH_BASES):
        raise ValueError(f"{path.name} reset address {pc:#x} is outside the image")
    return data


def load_assembly(path):
    data = path.read_bytes()
    if len(data) < 128 or len(data) % 4 or data[:8] != b"NFMRK2\0\0":
        raise ValueError(f"{path.name} is not a word-aligned NFMRK2 assembly")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native_build", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    try:
        booter = load_firmware(args.native_build / "nanoBooter.bin", 0, 0x8000)
        clr = load_firmware(args.native_build / "nanoCLR.bin", CLR_OFFSET, DEPLOY_OFFSET - CLR_OFFSET)
        corlib = load_assembly(args.output / "mscorlib.pe")
        if struct.unpack_from("<I", corlib, 20)[0] != CORLIB_CONTRACT:
            raise ValueError("mscorlib.pe native contract does not match the pinned nanoCLR")
        deployment = corlib + load_assembly(args.output / "UniClickerHello.pe")
        if len(deployment) + 8 > FLASH_SIZE - DEPLOY_OFFSET:
            raise ValueError("managed deployment leaves no room for the erased end marker")
    except (OSError, ValueError) as error:
        parser.error(str(error))

    image = bytearray(b"\xff" * FLASH_SIZE)
    image[:len(booter)] = booter
    image[CLR_OFFSET:CLR_OFFSET + len(clr)] = clr
    image[DEPLOY_OFFSET:DEPLOY_OFFSET + len(deployment)] = deployment
    (args.output / "uni-clicker-nano.bin").write_bytes(image)
    print(f"Packed {len(image)} flash bytes with {len(deployment)} bytes of managed assemblies.")


if __name__ == "__main__":
    main()
