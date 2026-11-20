set pagination off
set confirm off
set language c
monitor reset halt
maintenance flush register-cache

python
import gdb

def value(expression):
    return int(gdb.parse_and_eval(expression))

def word(address):
    return value(f"*(volatile unsigned int *)({address})")

def expect(description, actual, expected):
    if actual != expected:
        raise gdb.GdbError(f"{description}: got {actual!r}, expected {expected!r}")

image_vector = value("$uni_expected_vector")
msp = value("$uni_expected_msp")
expect("flash vector MSP", word(0x08000000), msp)
expect("flash reset vector", word(0x08000004), image_vector)
expect("reset PC", value("$pc"), image_vector & ~1)
expect("reset MSP", value("$msp"), msp)
expect("reset Thumb state", value("$xpsr") & (1 << 24), 1 << 24)
print(f"Reset PC {value('$pc'):#010x}, MSP {msp:#010x}")

micropython = bool(value("$uni_micropython"))
entry = value("$uni_entry") & ~1
emit = value("$uni_emit") & ~1
breakpoint = gdb.Breakpoint(f"*{entry:#x}", type=gdb.BP_HARDWARE_BREAKPOINT)
gdb.execute("continue")
expect("application entry", value("$pc"), entry)
inferior = gdb.selected_inferior()
if micropython:
    name = b"uni_hello.py\0"
    expect("frozen module", bytes(inferior.read_memory(value("$r0"), len(name))), name)
gdb.execute("info line *$pc")
breakpoint.delete()
gdb.execute("stepi")
if value("$pc") == entry:
    raise gdb.GdbError("single step did not advance the PC")
gdb.execute("info line *$pc")

breakpoint = gdb.Breakpoint(f"*{emit:#x}", type=gdb.BP_HARDWARE_BREAKPOINT)
pointer = "$r1" if micropython else "$r0"
greeting = b"Hello, UNI Clicker from MicroPython!\r\n" if micropython else b"Hello, UNI Clicker from NuttX!\0"
breakpoint.condition = f"*(unsigned int *)({pointer}) == 0x6c6c6548"
gdb.execute("continue")
expect("greeting output entry", value("$pc"), emit)
if micropython:
    expect("UART write length", value("$r2"), len(greeting))
expect("greeting", bytes(inferior.read_memory(value(pointer), len(greeting))), greeting)
expect("USART6 divisor", word(0x4001140c), 0x3aa)
expect("PC6/PC7 alternate mode", (word(0x40020800) >> 12) & 0xf, 0xa)
expect("PC6/PC7 AF8", word(0x40020820) >> 24, 0x88)
expect("CFSR", word(0xe000ed28), 0)
expect("HFSR", word(0xe000ed2c), 0)
print(f"Verified greeting: {greeting!r}, USART6 BRR=0x3aa, CFSR=0, HFSR=0")
gdb.execute("bt 6")
breakpoint.delete()
end
detach
