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
        raise gdb.GdbError(f"{description}: got {actual:#x}, expected {expected:#x}")

def check_faults():
    expect("CFSR", word(0xe000ed28), 0)
    expect("HFSR", word(0xe000ed2c), 0)

vector = value("$uni_expected_vector")
msp = value("$uni_expected_msp")
expect("flash vector MSP", word(0x08000000), msp)
expect("flash reset vector", word(0x08000004), vector)
expect("reset PC", value("$pc"), vector & ~1)
expect("reset MSP", value("$msp"), msp)
expect("reset Thumb state", value("$xpsr") & (1 << 24), 1 << 24)
check_faults()
print(f"Reset PC {value('$pc'):#010x}, MSP {msp:#010x}")

entry = value("$uni_entry") & ~1
breakpoint = gdb.Breakpoint(f"*{entry:#x}", type=gdb.BP_HARDWARE_BREAKPOINT)
gdb.execute("continue")
expect("application entry", value("$pc"), entry)
gdb.execute("info line *$pc")
gdb.execute("x/i $pc")
breakpoint.delete()
gdb.execute("stepi")
if value("$pc") == entry:
    raise gdb.GdbError("single step did not advance the PC")
print(f"Stepped to {value('$pc'):#010x}")
gdb.execute("info line *$pc")

heartbeat = value("$uni_heartbeat_address")
tx_bytes = value("$uni_tx_address")
expect("heartbeat starts at zero", word(heartbeat), 0)
expect("TX byte count starts at zero", word(tx_bytes), 0)
gdb.execute(f"watch -l *(unsigned int *){heartbeat:#x}")
banner_size = value("$uni_banner_size")
for edge, banners in ((1, 1), (2, 1), (3, 2)):
    gdb.execute("continue")
    expect("heartbeat edge", word(heartbeat), edge)
    expect("PD7 direction", (word(0x40020c00) >> 14) & 3, 1)
    expect("PD7 output", (word(0x40020c14) >> 7) & 1, edge & 1)
    expect("PC6/PC7 alternate mode", (word(0x40020800) >> 12) & 0x0f, 0x0a)
    expect("PC6/PC7 AF8", (word(0x40020820) >> 24) & 0xff, 0x88)
    expect("USART6 clock enable", (word(0x40023844) >> 5) & 1, 1)
    expect("USART6 enable, TX and RX", word(0x40011400) & 0x0d, 0x0d)
    expect("USART6 transmit complete", word(0x4001141c) & 0x40, 0x40)
    expect("USART6 TX byte counter", word(tx_bytes), banners * banner_size)
    check_faults()
    print(f"Edge {edge}: PD7={edge & 1}, TX bytes={banners * banner_size}, CFSR=0, HFSR=0")
expect("USART6 divisor for 16 MHz HSI at 115200 baud", word(0x4001140c), 139)
print(f"USART6 BRR {word(0x4001140c):#x}, VTOR {word(0xe000ed08):#010x}")
gdb.execute("bt 4")
gdb.execute("delete breakpoints")
end
detach
