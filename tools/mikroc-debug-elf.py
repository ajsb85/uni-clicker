"""Wrap the native mikroC image with source addresses from its compiler listing."""

import json
from pathlib import Path
import re
import struct
import subprocess
import sys


FLASH = 0x08000000
SOURCE = "examples/mikroc/hello.c"
ROUTINES = {"_main": "main", "hello_write_banner": "write_banner", "hello_wait_ms": "wait_ms"}
STATE = ("uni_heartbeat", "uni_tx_bytes")
SOURCE_LINE = re.compile(r"^;hello\.c,\s*(\d+)\s*::")
INSTRUCTION = re.compile(r"^(0x[0-9a-fA-F]+)\s+0x([0-9a-fA-F]{4}(?:[0-9a-fA-F]{4})?)\s+[A-Z][A-Z0-9.]*\s")
SYMBOL = re.compile(r"^(0x[0-9a-fA-F]+)\s+\[\s*\d+\]\s+(\w+)\s*$", re.MULTILINE)
SECTION = re.compile(r"^\s+\d+\s+\.\S+\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s", re.MULTILINE)


def listing_addresses(listing, image):
    code, symbols = listing.split("Symbol List:", 1)
    addresses = {name: int(address, 16) for address, name in SYMBOL.findall(symbols)}
    instructions = {}
    source_line = None
    for line in code.splitlines():
        if line.rstrip(":") in ROUTINES:
            source_line = None
        elif line.startswith("; end of"):
            source_line = None
        elif location := SOURCE_LINE.match(line):
            source_line = int(location[1])
        elif source_line and (instruction := INSTRUCTION.match(line)):
            address, opcode = int(instruction[1], 16), instruction[2]
            encoding = b"".join(
                struct.pack("<H", int(opcode[i:i + 4], 16)) for i in range(0, len(opcode), 4)
            )
            offset = address - FLASH
            if offset < 0 or image[offset:offset + len(encoding)] != encoding:
                raise ValueError(f"listing opcode differs from the image at {address:#x}")
            instructions[address] = source_line, opcode
    return addresses, instructions


def wrap(project):
    binary = project / "hello.bin"
    image = binary.read_bytes()
    hex_file = project / "hello.hex"
    sections = subprocess.check_output(["arm-none-eabi-objdump", "-b", "ihex", "-h", hex_file], text=True)
    layout = [(int(size, 16), int(address, 16)) for size, address in SECTION.findall(sections)]
    if layout != [(len(image), FLASH)] or not 8 <= len(image) <= 0x100000:
        raise ValueError("expected a single image at the start of STM32F746 flash")
    converted = project / "from-hex.bin"
    subprocess.run(["arm-none-eabi-objcopy", "-I", "ihex", "-O", "binary", hex_file, converted], check=True)
    if converted.read_bytes() != image:
        raise ValueError("native HEX and BIN disagree")

    _, reset = struct.unpack_from("<II", image)
    addresses, instructions = listing_addresses((project / "hello.lst").read_text(), image)
    main = addresses["_main"]
    if reset != (main | 1):
        raise ValueError("expected the native reset vector to point to main")
    declaration = instructions[main][0]
    app_entry = min(
        address for address, (line, _) in instructions.items() if address > main and line != declaration
    )
    labels = {addresses[native]: name for native, name in ROUTINES.items()}
    if not labels.keys() <= instructions.keys():
        raise ValueError("native routine entry is missing from the listing's source addresses")

    assembly = [".syntax unified", ".thumb", f".file 1 {json.dumps(SOURCE)}"]
    absolute_symbols = {name: addresses[f"_{name}"] for name in STATE}
    absolute_symbols["mikroc_app_entry"] = app_entry
    for name, address in absolute_symbols.items():
        assembly.extend([f".global {name}", f".set {name}, {address:#x}"])
    offset = 0
    previous_line = None
    for address, (line, opcode) in sorted(instructions.items()):
        start = address - FLASH
        if offset < start:
            # Ending the code section ends its DWARF range before raw vendor bytes.
            assembly.append(f'.section .image.{offset:08x},"a",%progbits')
            assembly.append(f".incbin {json.dumps(str(binary))}, {offset}, {start - offset}")
            previous_line = None
        if previous_line is None:
            assembly.append(f'.section .image.{start:08x},"ax",%progbits')
        if address in labels:
            name = labels[address]
            assembly.extend([f".global {name}", ".thumb_func", f"{name}:"])
        if line != previous_line:
            assembly.append(f".loc 1 {line} 0")
        width = "n" if len(opcode) == 4 else "w"
        assembly.append(f".inst.{width} 0x{opcode}")
        offset = start + len(opcode) // 2
        previous_line = line
    if offset < len(image):
        assembly.append(f'.section .image.{offset:08x},"a",%progbits')
        assembly.append(f".incbin {json.dumps(str(binary))}, {offset}, {len(image) - offset}")

    source = project / "debug-image.s"
    obj = project / "debug-image.o"
    elf = project / "hello.elf"
    linker = project / "debug-image.ld"
    source.write_text("\n".join(assembly) + "\n")
    linker.write_text(
        "PHDRS { flash PT_LOAD FLAGS(5); }\n"
        "SECTIONS { .text 0x08000000 : { *(SORT_BY_NAME(.image.*)) } :flash }\n"
    )
    subprocess.run(["arm-none-eabi-as", "-mcpu=cortex-m7", "--gdwarf-4", "-o", obj, source], check=True)
    subprocess.run(["arm-none-eabi-ld", "-T", linker, "-e", "main", "-o", elf, obj], check=True)
    subprocess.run(["arm-none-eabi-objcopy", "-O", "binary", elf, converted], check=True)
    if converted.read_bytes() != image:
        raise ValueError("debug ELF changed the native flash bytes")


if __name__ == "__main__":
    wrap(Path(sys.argv[1]).resolve())
