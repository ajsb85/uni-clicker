set pagination off
set confirm off
set language c
monitor reset halt
maintenance flush register-cache

python
import gdb

def value(expression):
    return int(gdb.parse_and_eval(expression))

def expect(description, actual, expected):
    if actual != expected:
        raise gdb.GdbError(f"{description}: got {actual:#x}, expected {expected:#x}")

def word(address):
    return value(f"*(volatile unsigned int *)({address})")

vector = value("$uni_expected_vector")
msp = value("$uni_expected_msp")
expect("nanoBooter vector MSP", word(0x08000000), msp)
expect("nanoBooter reset vector", word(0x08000004), vector)
expect("reset PC", value("$pc"), vector & ~1)
expect("reset MSP", value("$msp"), msp)
expect("reset Thumb state", value("$xpsr") & (1 << 24), 1 << 24)
print(f"nanoBooter reset PC {value('$pc'):#010x}, MSP {msp:#010x}")

entry = value("$uni_entry") & ~1
breakpoint = gdb.Breakpoint(f"*{entry:#x}", type=gdb.BP_HARDWARE_BREAKPOINT)
breakpoint.condition = "*(unsigned int *)$r0 == 0x6c6c6548"
greeting = b"Hello, UNI Clicker from .NET nanoFramework!\0"
for repeat in (1, 2):
    gdb.execute("continue")
    address = value("$r0")
    if bytes(gdb.selected_inferior().read_memory(address, len(greeting))) != greeting:
        raise gdb.GdbError("unexpected managed greeting at the native Emit entry")
    expect("nanoCLR VTOR", word(0xe000ed08), 0x00210000)
    expect("USART6 divisor", word(0x4001140c), 0x8b)
    expect("CFSR", word(0xe000ed28), 0)
    expect("HFSR", word(0xe000ed2c), 0)
    print(f"Managed greeting {repeat}")
    gdb.execute("x/s $r0")
    if repeat == 1:
        gdb.execute("bt 4")
        gdb.execute("stepi")
        if value("$pc") == entry:
            raise gdb.GdbError("single step did not advance the PC")
breakpoint.delete()
end
detach
