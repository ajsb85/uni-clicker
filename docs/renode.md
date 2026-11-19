# Renode on the UNI Clicker bench

The checked-in [platform](../sim/uni-clicker.repl) models Cortex-M7, the F746ZG flash and RAM sizes, 16 MHz SysTick, RCC/RTC, GPIO C and D, LED C, and USART6. It runs offline. The upstream Discovery model lives at `$UNI_WINDOWS_ROOT/renode/renode/platforms/cpus/stm32f746.repl`. Its companion scripts are in `scripts/single-node/stm32f746*.resc`. Use them as model references for added peripherals. The checked-in model uses the UNI Clicker pins and memory geometry.

## Four ways to run the same ELF

```bash
source tools/bench-env.sh
make rust
tools/simulate.sh rust
tools/simulate.sh rust gpio
tools/simulate.sh rust trace
tools/simulate.sh rust gdb
```

| Mode | What it checks or captures |
| --- | --- |
| `smoke` | Runs 1.4 virtual seconds and compares both greetings byte for byte, including CRLF |
| `gpio` | Samples the PD7 output register at 0.6, 1.2 and 1.7 virtual seconds and asserts high, low, high |
| `trace` | Records PC and opcode for the first 2 ms, plus accesses to USART6 |
| `gdb` | Opens a monitor and starts a simulator GDB server on port 3334 |

Each run has its own `.cache/sim/<profile>.<mode>.*` directory with the monitor script, UART transcript and config. The bounded runs keep their monitor log. Compare `uart.txt` to `expected.txt`, or inspect `boot.trace` and logs alongside `arm-none-eabi-objdump -dSl build/rust/hello.elf`. Keep long traces off when testing repeated output.

## Debug an emulated startup

Leave the `gdb` mode open in terminal one. In terminal two, resolve the entry symbol from the same ELF. The following commands are for the Rust example.

```bash
entry=$(arm-none-eabi-nm build/rust/hello.elf | awk '$3 == "main" {print "0x" $1}')
gdb-multiarch -q -nx build/rust/hello.elf \
  -ex 'target remote 127.0.0.1:3334' -ex "break *$entry"
```

```gdb
monitor start
continue
stepi
info line *$pc
info registers pc msp xpsr
x/2wx 0x08000000
detach
```

Quit Renode at the monitor when done. Use port 3333 for the real OpenOCD target and 3334 for Renode. Start a fresh simulator run when changing firmware so the peripherals, RAM, and virtual time begin from a known state.

The native mikroC profile uses the ELF that `make mikroc` creates from the vendor BIN and listing. Its flash bytes match the vendor HEX. In `tools/simulate.sh mikroc gdb`, connect GDB to port 3334 with `build/mikroc/hello.elf` and set `break hello.c:32`. `continue` stops after the compiler's startup calls. `stepi` advances to line 34 in the tested build. GDB printed an SP alias warning while stepping in Renode and still resolved both addresses. The same recipe's `smoke`, `gpio`, and `trace` modes check the two greetings, the LED state, and the native startup opcodes. [Native build and verification details](mikroe.md)

The model maps flash through the AXI address `0x08000000` and the ITCM alias `0x00200000`. RIOT uses a modeled TIM2 compare interrupt. The PLL model configures 216 MHz SysTick, USART6 at 108 MHz, and TIM5 at 108 MHz for Mbed OS, MicroPython and NuttX. `tools/simulate.sh nuttx` expects one startup line. The other runtime profiles expect two greetings and support the timed PD7 check. [Framework configuration](frameworks.md)

## Add a peripheral or interactive test

The workspace includes the Renode testing APIs at `$UNI_WINDOWS_ROOT/renode/renode-docs/source/basic/renode-testing-api.md`. In a Robot test, use `Create Terminal Tester    sysbus.usart6` before `Start Emulation`. Use `Wait For Line On Uart` for a greeting or prompt and `Write Line To Uart` for an input-driven application. A UART receive test needs an app that actually reads USART6. For LED assertions, the model's LED is `sysbus.gpioD.ledC`. Use `Assert Led State` or `Assert Led Is Blinking` after creating an LED tester.

For register traffic, run `using sysbus` then `sysbus LogPeripheralAccess usart6 true` and a short `emulation RunFor`. Use the upstream board model and local SVD to locate the addresses, and check that any new REPL peripheral exposes the registers and IRQs used by the firmware. A SVD supplies names for debugging, while a peripheral model supplies behavior.

Use Robot for multi-step UART or GPIO interaction, and the shell smoke test for repeatable output. The model has fixed clocks and does not implement the board's physical USB, SWD mux, electrical behavior or every F746 peripheral. Cover those paths on the real bench and record hardware and simulator evidence separately.
