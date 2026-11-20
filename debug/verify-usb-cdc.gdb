set confirm off
set pagination off
set language c
monitor reset halt
maintenance flush register-cache

python
import gdb

def word(address):
    return int(gdb.parse_and_eval(f"*(volatile unsigned int *){address:#x}"))

def expect(description, actual, expected):
    if actual != expected:
        raise gdb.GdbError(f"{description}: got {actual:#x}, expected {expected:#x}")

bp = gdb.Breakpoint("setup", type=gdb.BP_HARDWARE_BREAKPOINT)
gdb.execute("continue")
gdb.execute("info line *$pc")
bp.delete()
gdb.execute("stepi")
gdb.execute("watch -l uni_usb_ready")
gdb.execute("continue")
expect("USB CDC setup finished", int(gdb.parse_and_eval("uni_usb_ready")), 1)
expect("PB15 output mode", word(0x40020400) >> 30, 1)
expect("USB PSW high", (word(0x40020414) >> 15) & 1, 1)
expect("PA11 and PA12 alternate function", (word(0x40020024) >> 12) & 0xff, 0xaa)
pll = word(0x40023804)
expect("HSE PLL source", (pll >> 22) & 1, 1)
expect("PLLM", pll & 0x3f, 25)
expect("PLLN", (pll >> 6) & 0x1ff, 384)
expect("PLLQ for USB 48 MHz", (pll >> 24) & 0xf, 8)
expect("CPU clock in Hz", int(gdb.parse_and_eval("SystemCoreClock")), 96000000)
expect("OTG core current mode is device", word(0x50000014) & 1, 0)
expect("CFSR", word(0xe000ed28), 0)
expect("HFSR", word(0xe000ed2c), 0)
print("USB device mode, role pin, USB clock and fault registers verified.")
gdb.execute("delete breakpoints")
end
detach
