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

vector = value("$uni_expected_vector")
msp = value("$uni_expected_msp")
expect("flash vector MSP", word(0x08000000), msp)
expect("flash reset vector", word(0x08000004), vector)
expect("reset PC", value("$pc"), vector & ~1)
expect("reset MSP", value("$msp"), msp)
expect("reset Thumb state", value("$xpsr") & (1 << 24), 1 << 24)

entry = value("$uni_entry") & ~1
breakpoint = gdb.Breakpoint(f"*{entry:#x}", type=gdb.BP_HARDWARE_BREAKPOINT)
gdb.execute("continue")
expect("application entry", value("$pc"), entry)
gdb.execute("info line *$pc")
breakpoint.delete()
gdb.execute("stepi")
if value("$pc") == entry:
    raise gdb.GdbError("single step did not advance the PC")
gdb.execute("info line *$pc")

ready = value("$uni_ready_address")
expect("console starts unready", word(ready), 0)
gdb.execute(f"watch -l *(unsigned int *){ready:#x}")
gdb.execute("continue")
expect("console ready", word(ready), 1)
expect("USART6 ready banner bytes", word(value("$uni_tx_address")), value("$uni_banner_size"))
expect("USART6 RX interrupt", word(0x40011400) & 0x2d, 0x2d)
expect("USART6 NVIC IRQ 71", word(0xe000e108) & 0x80, 0x80)
expect("USART6 IRQ 71 vector", word(word(0xe000ed08) + 4 * (16 + 71)),
       value("(unsigned int)&USART6_IRQHandler") | 1)
expect("USART6 IRQ 71 priority", word(0xe000e444) >> 24, 0x50)
expect("USART6 GPIO mode", (word(0x40020800) >> 12) & 0xf, 0xa)
expect("USART6 GPIO PC6/PC7 AF8", (word(0x40020820) >> 24) & 0xff, 0x88)
expect("USART6 divisor for 115200 baud", word(0x4001140c), 0x8b)
expect("USART6 transmit complete", word(0x4001141c) & 0x40, 0x40)
expect("CFSR", word(0xe000ed28), 0)
expect("HFSR", word(0xe000ed2c), 0)
print("USART6 ready, RX interrupt enabled, CFSR=0, HFSR=0")
gdb.execute("bt 4")
gdb.execute("delete breakpoints")
end
detach
