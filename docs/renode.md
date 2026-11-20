# Renode development handoff

Start in the WSL Git checkout at `/home/gbast/uni-clicker`. The Windows workspace at `/mnt/c/Users/gbast/dev/uni-clicker` supplies the SDKs, hardware manuals, and upstream checkouts. If WSL restarted, check the SDK mount before sourcing the environment. [Remount command and Windows tool paths](../AGENT.MD#start-a-fresh-session)

```bash
cd /home/gbast/uni-clicker
git status --short --branch
df -h . .cache/sdk-native
source tools/bench-env.sh
"$RENODE" --version
make cli
cli=build/cli/debug/uni-cli
"$cli" check rust
"$cli" check freertos-console --trace
"$cli" systemview
```

The local portable runner is Renode **1.17.0**, build `1.17.0+20260907gitf1dd1b4af`, at `.cache/tools/renode/renode`. Each CLI check records the runner version and firmware SHA-256 in `provenance.tsv`. GitHub Actions records the pinned Linux archive SHA-256 and SDK revisions, then runs the tests with cached Cargo dependencies and local simulation inputs. [Firmware simulation workflow](../.github/workflows/firmware.yml)

## Choose the platform

| Model | Use | Modeled hardware |
| --- | --- | --- |
| [uni-clicker.repl](../sim/uni-clicker.repl) | Most greeting, console, and trace examples | Cortex-M7, 1 MiB flash at `0x08000000` with an ITCM alias at `0x00200000`, contiguous SRAM through `0x2004ffff`, NVIC, 16 MHz SysTick, RCC/RTC, configurable CRC, GPIO C/D, PD7 LED C, USART6 and TIM2 |
| [uni-clicker-pll.repl](../sim/uni-clicker-pll.repl) | Mbed OS, MicroPython and NuttX | Base platform with 216 MHz SysTick, USART6 at 108 MHz, and TIM5 at 108 MHz on IRQ 50 |
| `platforms/cpus/stm32f746.repl` in the installed runner or upstream checkout | Reference for adding STM32 peripherals | F746 model used by upstream platforms. Check aliases, clocks, IRQs, pins and peripheral coverage against the UNI Clicker. |

USART6 is `sysbus.usart6` at `0x40011400` on IRQ 71. PD7 is `sysbus.gpioD.ledC`, with GPIOD ODR at `0x40020c14`. TIM2 is `sysbus.timer2` at `0x40000000` on IRQ 28. The model configures the CPU at 16 MIPS. The timers and tests use Renode virtual time. Measure physical execution timing on the STM32F746ZG.

## Local sources and manuals

| Resource | Verified bench path |
| --- | --- |
| Runner, platforms and bundled tests | `.cache/tools/renode/{renode,renode-test,platforms,scripts,tests}` |
| Upstream examples | `$UNI_WINDOWS_ROOT/renode/renode/` at `22fbc559`. See `platforms/cpus/stm32f746.repl` and `scripts/single-node/stm32f746*.resc`. |
| Upstream docs | `$UNI_WINDOWS_ROOT/renode/renode-docs/source/` at `3da81a1d` |
| Peripheral implementations | `$UNI_WINDOWS_ROOT/renode/renode-infrastructure/src/Emulator/Peripherals/Peripherals/` at `38fb573a`. Start with `UART/STM32F7_USART.cs`, `Timers/STM32_Timer.cs`, `Miscellaneous/STM32F4_RCC.cs`, and `CRC/STM32_CRC.cs`. |
| Supporting upstream checkouts | `$UNI_WINDOWS_ROOT/renode/{renode-resources,renode-issue-reproduction-template,renode-docker,zephyr-samples-builder,homebrew-tap}` |
| Hardware definitions | `$UNI_WINDOWS_ROOT/STM32F746.svd`, `stm32f746.svd.patched`, `STM32F7_svd/`, and the local RM0385 and PM0253 PDFs |
| Board reference exports | `.cache/references/uni-clicker/README.md` links the text exports for all four board PDFs and images of both schematics. Rebuild with `tools/export-board-references.sh`. |

Read `advanced/platform_description_format.md` for REPL attributes and connections, `advanced/writing-peripherals.md` for register implementations, and `advanced/time_framework.md` and `advanced/virtual_time_scheduling_mechanisms.md` for time sources. See `basic/monitor-syntax.md` and `basic/using-python.md` for monitor commands and hooks. For debugging and traces, see `debugging/gdb.md` and the `execution-tracing/` section. For host I/O and tests, see `basic/renode-testing-api.md` and `host-integration/uart.md`. Some stock demonstration scripts fetch a firmware image. Use the local ELF loaded by the project scripts for offline checks.

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

Use `UNI_SIM_ELF=/absolute/path/to/firmware.elf tools/simulate.sh rust smoke` to test an alternate ELF with the Rust greeting contract. PlatformIO profiles pass their build ELF through the same variable. The shell `trace` mode captures opcodes and USART6 bus access. The CLI `check <profile> --trace` mode builds Tonbandgeraet instrumentation for STM32Cube, FreeRTOS, or the FreeRTOS console.

## Interactive and timing checks

| Check | What it exercises | Artifacts |
| --- | --- | --- |
| `uni-cli check freertos-console --trace` | `tools/simulate-console.py` injects USART6 bytes at defined times. `tools/simulate-console-live.py` drives the same firmware through a private Renode pseudoterminal using the host regression driver. The checks cover malformed input, PD7 commands and burst accounting. | `trace/uart.txt`, decoded events, `trace/latency.tsv`, `trace/uni.perfetto-trace`, and the live driver output under `trace/live/` |
| `uni-cli check stm32cube --trace` and `uni-cli check freertos --trace` | `tools/check-tonbandgeraet.sh` builds instrumented firmware, exports the SRAM capture, and asserts delay or queue events. | `trace/hello.elf`, `trace/sram.bin`, decoded events and Perfetto trace |
| `uni-cli systemview` | `tools/simulate-systemview.py` exercises RTT channels, sends start and stop, and verifies PD7 markers and terminal output. | `.cache/verification/systemview.*/renode/{trace.bin,events.jsonl,summary.json,terminal.txt}` |
| `tools/simulate.sh nanoframework-native` | `tools/simulate-nanoframework.sh` uses a CPU hook at the managed output call after booting the full image. | `wire-protocol.bin` and the decoded greeting in `renode.log` |

On failure, open `report.tsv` and the failing stage log first. Keep the generated `run.resc`, ELF and map, transcript, simulator log, and relevant trace excerpts in the report directory. Record the active model, clock, and virtual time used for the checks.

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
info registers pc sp xpsr
x/2wx 0x08000000
detach
```

Quit Renode at the monitor when done. Use port 3333 for the real OpenOCD target and 3334 for Renode. Start a fresh simulator run when changing firmware so the peripherals, RAM, and virtual time begin from a known state. Renode may already be started on attach. In the Rust example, compare the flash vector's initial stack value `0x20050000` with the active `sp` at reset. The separately named `msp` register can display zero through the Renode GDB stub.

The native mikroC profile uses the ELF that `make mikroc` creates from the vendor BIN and listing. Its flash bytes match the vendor HEX. In `tools/simulate.sh mikroc gdb`, connect GDB to port 3334 with `build/mikroc/hello.elf` and set `break hello.c:32`. `continue` stops after the compiler's startup calls. `stepi` advances to line 34 in the tested build. GDB printed an SP alias warning while stepping in Renode and still resolved both addresses. The same recipe's `smoke`, `gpio`, and `trace` modes check the two greetings, the LED state, and the native startup opcodes. [Native build and verification details](mikroe.md)

The model maps flash through the AXI address `0x08000000` and the ITCM alias `0x00200000`. RIOT uses a modeled TIM2 compare interrupt. The PLL model configures 216 MHz SysTick, USART6 at 108 MHz, and TIM5 at 108 MHz for Mbed OS, MicroPython and NuttX. `tools/simulate.sh nuttx` expects one startup line. MicroPython emits two greetings and supports the timed PD7 check. [Framework configuration](frameworks.md)

## nanoFramework boot and managed output

`tools/simulate.sh nanoframework-native` loads the full flash BIN, resets through nanoBooter, and runs for six virtual seconds. A CPU hook reads the managed string at the native CLR output call. The check requires two exact greetings, CLR VTOR `0x00210000`, clear CFSR and HFSR, and a nanoFramework Wire Protocol capture on USART6. The encoded Wire Protocol frames are in `wire-protocol.bin`. The managed text checked at dispatch is in `renode.log`. The STM32 CRC peripheral is required because the runtime uses it for assembly header and image validation.

`tools/simulate.sh nanoframework-native gdb` starts an interactive GDB server. Inspect nanoBooter first with its ELF, and use `nanoCLR.elf` for `CLRStartupThread` and the managed-to-native call. Resolve the emitter address from that ELF with `arm-none-eabi-nm` and the symbol `_ZN9CLR_Debug4EmitEPKci.part.0` from the pinned toolchain. [Native image and bench commands](frameworks.md#net-nanoframework)

## Add a peripheral or interactive test

The workspace includes the Renode testing APIs at `$UNI_WINDOWS_ROOT/renode/renode-docs/source/basic/renode-testing-api.md`. In a Robot test, use `Create Terminal Tester    sysbus.usart6` before `Start Emulation`. Use `Wait For Line On Uart` for a greeting or prompt and `Write Line To Uart` for an input-driven application. A UART receive test needs an app that actually reads USART6. For LED assertions, the model's LED is `sysbus.gpioD.ledC`. Use `Assert Led State` or `Assert Led Is Blinking` after creating an LED tester.

For register traffic, run `using sysbus` then `sysbus LogPeripheralAccess usart6 true` and a short `emulation RunFor`. Use the upstream board model and local SVD to locate the addresses, and check that any new REPL peripheral exposes the registers and IRQs used by the firmware. A SVD supplies names for debugging, while a peripheral model supplies behavior.

The bundled examples `tests/peripherals/STM32_UART.robot` and `tests/unit-tests/host-uart.robot` show direct UART injection and pseudoterminal setup. The packaged `renode-test` launcher and its Python requirements are present locally. Robot Framework needs a workspace virtual environment with the packages pinned in `tests/requirements.txt`. The CLI checks above use Bash and the Python standard library.

1. Find the register range, interrupt, reset values, access widths, clock and pin routes in the local SVD, RM0385 and both board schematics. Check the matching Renode class and an upstream peripheral test before extending it.
2. Start the feature in a small REPL overlay with `using "uni-clicker.repl"` alongside the base file. See the [PLL overlay](../sim/uni-clicker-pll.repl) for object overrides and IRQ wiring.
3. Exercise a success case and a timeout or error. Advance with `emulation RunFor`, log the peripheral of interest, and read the resulting register, IRQ, or GPIO state. The nanoFramework runner shows a CPU hook at an ELF symbol. Read CFSR at `0xe000ed28` and HFSR at `0xe000ed2c` after a failing run.
4. Add a repeatable assertion through the existing runner or a Robot suite. Run the Rust GPIO and boot trace, then the console and SystemView checks when the change touches clocks, IRQs, or SRAM. Test USB-C enumeration and power roles, the programming mux, electrical behavior, and physical latency on the bench.

## Bench status and open checks

- Firmware source baseline `114a3b7` passed the hosted regressions with downloadable reports. [GitHub Actions run and artifacts](https://github.com/ajsb85/uni-clicker/actions/runs/44663924138)
- The board was left running the verified Arduino USB CDC example. Windows assigned it COM4 under `0483:5740`. The bench logs are under `.cache/verification/usb-cdc.NQokN5/`. For an OTG_FS simulation extension, check `USB/DesignWare_USB_OTG/` in the infrastructure checkout and the F746 register and IRQ definitions. Hardware uses PB15 high for device mode, PA11/PA12 for data, and a 48 MHz PLL clock. [USB-C bench guide](usb-cdc.md)
- The simulated USART6 workload and the physical debugger boot check passed. The physical command workload needs a confirmed 3.3 V adapter COM port at J2.16/J2.15. Measure that latency baseline before adding SystemView markers to the console workload. The separate SystemView demo already supports live RTT capture over ST-LINK. [USART6 wiring, commands and report paths](../AGENT.MD#timing-captures-and-usart6-console)
