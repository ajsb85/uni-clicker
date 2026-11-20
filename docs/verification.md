# Verification on 2026-11-19

The bench used a UNI Clicker with the SiBRAIN STM32F746ZG card, Windows 11 with the ST-LINK USB device, and Ubuntu 26.04.1 under WSL2. STM32CubeProgrammer 2.24.0 detected device ID `0x449`, revision Z, Cortex-M7, and 1 MiB flash. The pre-lab 1 MiB flash image was saved locally before programming.

## What each check measures

1. BIN and ELF inspection determines the initial MSP and Thumb reset vector, section sizes, the application entry, and the two SRAM debug symbols.
2. CubeProgrammer programs the selected BIN and verifies it against flash.
3. OpenOCD resets and halts the Cortex-M7. GDB invalidates its register cache after the monitor command, compares the flash vectors to the BIN, and verifies the initial PC, MSP and Thumb state.
4. GDB sets a hardware breakpoint at application entry, resolves the source position, single-steps an instruction, and checks that the SRAM counters start at zero.
5. A hardware watchpoint stops each of the first three heartbeat writes. GDB verifies the PD7 output mode and values `1, 0, 1`, PC6 and PC7 in AF8, the USART6 clock gate and transmit-complete bit, the expected byte counts, and zero CFSR and HFSR. The USART6 baud divisor was `0x8b`.
6. Renode captures the precise greeting bytes, including CRLF, from the same ELF. The physical SWD check observes firmware and peripheral state. The UART transcript comes from the simulator.

The probe reported eight hardware breakpoints and four watchpoints. GDB initially displayed a cached pre-reset PC even though OpenOCD had halted at the correct reset address. Invalidating the register cache resolved the discrepancy.

STM32CubeProgrammer independently halted the C image at `0x080002e0`, read MSP `0x20050000` and xPSR `0x01000000`, single-stepped the reset handler to `0x080002e4`, and resumed the core. The ST-LINK CLI shipped with mikroProg Suite also listed the same V2 probe.

Arduino CLI 1.5.0 built against STM32duino 3.1.0. Its `--optimize-for-debug` mode emits DWARF source locations with `-Og -g`. The sketch instantiates the core's concrete `Uart` class for PC7 and PC6.

Swift 6.4.2 enforces `-no-allocations` and emits separate function sections so the ELF link can discard unused runtime helpers. The Swift C ABI entry has no source line. Single-stepping that entry reaches the first line in `Hello.swift`.

## Results

Every image passed flash readback, the physical GDB checks, and the exact Renode UART comparison. Each had initial MSP `0x20050000`.

| Image | BIN bytes | Reset PC | Application entry | USART6 bytes at edges 1, 2, 3 |
| --- | ---: | --- | --- | --- |
| STM32Cube | 4,140 | `0x080002e0` | `main` | 36, 36, 72 |
| Arduino | 23,832 | `0x08003bb4` | `setup` | 34, 34, 68 |
| Rust | 1,632 | `0x08000400` | `main` | 31, 31, 62 |
| Embedded Swift | 916 | `0x080002c4` | `uni_swift_main` | 41, 41, 82 |

The host CLI resolves the entry and SRAM addresses from the ELF before GDB uses them. GDB's expression parser otherwise depends on the source language of the frame where the initial probe attachment stops.

Other versions used were GNU Arm Embedded GCC 14.2.1, Rust 1.99.1, OpenOCD xPack 0.12.0-7, GDB 17.1, and Renode 1.17.0.

After the debugger detached, two CubeProgrammer hot-plug reads confirmed the Swift image was still running. Its heartbeat advanced from 55 to 57 and its TX byte counter advanced from 1,148 to 1,189.

## Extended firmware results

The following builds passed CubeProgrammer byte readback, the three GDB hardware watchpoints and USART6 register checks, and exact Renode UART output. All used initial MSP `0x20050000`, UART BRR `0x8b`, and reported zero CFSR and HFSR.

| Image | BIN bytes | Reset PC | USART6 bytes at edges 1, 2, 3 |
| --- | ---: | --- | --- |
| Zig / MicroZig | 936 | `0x080001c8` | 30, 30, 60 |
| NECTO / mikroSDK | 1,405 | `0x08000504` | 32, 32, 64 |
| NECTO Windows compiler | 1,405 | `0x08000504` | 32, 32, 64 |
| FreeRTOS | 3,836 | `0x08000294` | 35, 35, 70 |
| Eclipse ThreadX | 4,519 | `0x0800029c` | 34, 34, 68 |
| libopencm3 | 1,556 | `0x08000438` | 37, 37, 74 |

The Windows NECTO GCC image was byte-identical to the WSL GCC image. The NECTO ST-LINK GDB server separately attached to the running WSL-built NECTO firmware, read the reset vectors, and single-stepped the source line in `wait_ms`. The Windows GCC ELF preserves source locations with the WSL UNC prefix.

Renode's Rust GPIO scenario observed high, low, high at the three specified virtual times. Its trace scenario captured instruction and UART activity, and the GDB scenario stepped from the Cortex-M reset path to the Rust entry source. See [Renode usage](renode.md).

## Native mikroC PRO for ARM

The elevated Windows IDE built the staged project with the ARM license dongle attached. Replaying the IDE's raw command through PowerShell produced identical native HEX and BIN from WSL. This resolved the earlier standalone source-file error 340. [Mikroe reproduction notes](mikroe.md)

| Check | Observed result |
| --- | --- |
| Flash and separate full-image readback | 1,024 bytes at `0x08000000`, SHA-256 `7c841aaa2e4ba5355ef156bf43e3d4bbfe96f7cda8ebebc957acb2b6af4dce38` |
| Reset vector and initial MSP | `0x080002c9` and `0x2004fffc`, actual reset PC `0x080002c8` |
| Hardware source step | `hello.c:32` at `0x080002d2` to `hello.c:34` at `0x080002d6`, matched to the native listing |
| Hardware watchpoints | PD7 `1, 0, 1`, TX byte counts `33, 33, 66`, USART6 BRR `0x8b`, zero CFSR and HFSR |
| Running after GDB detached | Hot-plug reads showed heartbeat `154 → 156` and TX byte count `2574 → 2607` |
| Renode | Two exact CRLF greetings, PD7 high/low/high, reset instruction trace, and the `hello.c:32` to `hello.c:34` GDB step |

The native mikroC image was left running on the board. The physical UART check covered USART6 configuration and transmit completion via SWD. Renode captured the UART bytes. The separately named `mikroc-source-check` profile builds the same application with a GCC/CMSIS adapter. Its 812-byte image also passed flash readback, source stepping, PD7 watchpoints, and Renode UART. Its reset PC was `0x080002b4`.

## UNI Clicker framework ports

The following images passed CubeProgrammer flash verification, source stepping, three hardware PD7 watchpoints, and the exact Renode UART and timed GPIO checks. All reported zero CFSR and HFSR.

| Profile | BIN bytes | Reset PC | USART6 divisor | TX byte count at edges 1, 2, 3 |
| --- | ---: | --- | --- | --- |
| Zephyr | 17,848 | `0x08000954` | `0x8b` | 33, 33, 66 |
| RIOT | 10,356 | `0x080007e4` | `0x8a` | 31, 31, 62 |
| ChibiOS | 6,128 | `0x002002d8` | `0x8b` | 34, 34, 68 |
| Mbed OS | 41,568 | `0x08004934` | `0x3aa` | 34, 34, 68 |

RIOT truncates the divisor at 16 MHz. The ChibiOS driver clears TC and signals `CHN_TRANSMISSION_END` in the UART interrupt. The application increments its byte counter after that event. Mbed OS uses USART6 at 108 MHz and the TIM5 microsecond ticker. [Build and debugger details](frameworks.md)

NuttX flashed and verified a 125,396-byte BIN. GDB reset at `0x0800039c` with MSP `0x20011a4c`, then stopped and stepped at the `puts` line in `unihello_main`. It read PC6 and PC7 in AF8, USART6 BRR `0x3aa`, and zero CFSR and HFSR. Renode captured the one startup greeting exactly.

MicroPython passed HEX verification and reset at `0x0802011c` with MSP `0x2004fff8`. GDB stepped into the frozen `uni_hello.py` startup and inspected 38 bytes containing the complete CRLF greeting inside `uart_tx_data`. The backtrace included the bytecode interpreter and the `machine.UART.write` path. USART6 BRR was `0x3aa`, and CFSR and HFSR were zero. Renode captured both greetings and PD7 high, low, high.

The .NET nanoFramework managed application built with Windows `dotnet.exe` and printed five greetings in the POSIX runtime pinned at `e903edb`. The compatible `mscorlib.pe` uses `NFMRK2` and native contract hash `0x532e6934`. [Managed build and runtime instructions](frameworks.md)

The native build produced a 1 MiB combined image. CubeProgrammer verified it at `0x08000000`. The MCU reset through nanoBooter at `0x00203674` with MSP `0x20000400`, then switched VTOR to the nanoCLR vector table at `0x00210000`. The batch GDB check stopped twice in `CLR_Debug::Emit`, read the full C# greeting each time, and stepped one native instruction. Both stops showed USART6 BRR `0x8b` and zero CFSR and HFSR. The optimized ChibiOS thread wrapper marks the end of GDB's backtrace. The physical board was left running this image. Bench logs are in `.cache/verification/nanoframework-native.wXySm1`. [Native build and SWD commands](frameworks.md#native-uni-clicker-image)

Renode ran the same BIN through the native CLR and observed two exact managed greetings with the STM32 CRC model in place. The Wire Protocol capture contained the `NFPKTV1` header. The simulator asserted the managed text at the CLR dispatch point and verified VTOR and the fault registers. A separate GDB session stopped at the output call and stepped from `0x0023a508` to `0x0023a50c` while reporting its Cortex-M stack-pointer alias warning. [Renode procedure](renode.md#nanoframework-boot-and-managed-output)

## PlatformIO 20.0.0 results

All five environments built with PlatformIO Core 6.2.0, passed the PlatformIO `renode` target, and passed physical CubeProgrammer and SWD verification. The hardware checks showed PD7 high, low, high and zero CFSR and HFSR.

| Environment | Reset PC | TX byte count at edges 1, 2, 3 |
| --- | --- | --- |
| Arduino | `0x08003970` | 34, 34, 68 |
| STM32Cube | `0x08001160` | 36, 36, 72 |
| CMSIS | `0x08000208` | 32, 32, 64 |
| libopencm3 | `0x0800046c` | 37, 37, 74 |
| Zephyr | `0x08000f84` | 33, 33, 66 |

The batch files are in `.cache/verification/bench.57p0Ky` and `.cache/verification/bench.p8K6L2`. [PlatformIO reproduction](platformio.md)

## Headless CLI recheck on 2026-11-20

`uni-cli check stm32cube` took 4.5 seconds with a current build and 7.4 seconds when it rebuilt the firmware. `uni-cli check mikroc` ran the licensed Windows compiler and passed in 8.6 seconds. These checks include ELF analysis and Renode smoke output. [CLI workflow](../README.md#run-a-firmware-check)

`uni-cli check nanoframework-native --hardware` passed all stages in 224 seconds, including 137 seconds for the physical stage. The build produced the same 1 MiB image as the prior run. CubeProgrammer verified the flash contents, and the OpenOCD and GDB check read both exact managed greetings and verified the fault registers. The per-stage logs are under `.cache/verification/check.nanoframework-native.1795137318837577190.1009303`. [Native build and verification](frameworks.md#native-uni-clicker-image)

## Arduino and native Rust programming

Arduino CLI 1.5.0 ran the STM32duino 3.1.0 `swdMethod` recipe and reached the Windows CubeProgrammer through the workspace adapter. CubeProgrammer verified the 23,832-byte sketch image. The Arm GDB bundled with Arduino's xPack GCC connected to Windows OpenOCD, stopped at `setup()`, and stepped from line 22 to line 23 of the sketch. The bench check confirmed PD7 high, low, high, USART6 TX counters of 34, 34, and 68, and zero CFSR and HFSR. Logs are under `.cache/verification/arduino-native.j1Vwag`. [Arduino CLI commands](../AGENT.MD#arduino-cli-upload-and-debugger)

Windows probe-rs 0.32.0 found the ST-LINK at `0483:3748` and programmed the Rust ELF at 240 kHz. It reported 1.16 seconds for the verified download, and a separate `probe-rs verify` passed. The companion `cargo-flash.exe` succeeded with `--preverify --verify` on the same ELF. The companion `cargo-embed.exe` reported its version. [Native Rust commands](../AGENT.MD#native-rust-flashing-and-debugging)

An unchanged-image `probe-rs download --preverify --verify` took 0.25 seconds. `mi meta` returned parseable JSON, and `mi info` was unable to auto-identify the F746ZG. Both `uni-cli check arduino` and `uni-cli check rust` passed the build, ELF analysis and Renode stages.

WSL `rust-gdb` with `gdb-multiarch` connected to the Windows probe-rs GDB server on port 1337. It read reset vector `0x08000401` and initial MSP `0x20050000`, stopped at the Rust entry on `src/main.rs:78`, and advanced the PC from `0x080005a0` to `0x080005a2`. Direct `probe-rs read` returned zero CFSR and HFSR. The GDB stub returned a memory access error at that address. OpenOCD and `rust-gdb` passed the full bench check with PD7 high, low, high and USART6 TX counters of 31, 31, and 62. Logs are under `.cache/verification/probe-rs-windows.wotpfL`. The board was left running the Rust image.

## Unified hardware and timing checks

`uni-cli check rust --hardware --programmer probe-rs` passed native preverification and readback, reset, and OpenOCD GPIO/UART verification. The native programmer read MCU ID `0x449` and 1,024 KiB before allowing flash. The separate `uni-cli test rust --hardware` suite passed all five embedded-test cases while carrying RTT messages over ST-LINK. The suite verified PD7 high and low, three SysTick IRQs, USART6 transmission, clear fault registers, and an expected panic. The test log is in `.cache/verification/rust-board.dweheu/`.

`uni-cli check nuttx --hardware` and `uni-cli check micropython --hardware` passed build, analysis, Renode and SWD. NuttX hit `unihello_main` and confirmed the string passed to `puts`. MicroPython flashed the split Intel HEX and confirmed that the frozen module passed its 38-byte CRLF greeting to `uart_tx_data`. The CLI unit tests exercised split-image reconstruction and corruption rejection.

The STM32Cube and FreeRTOS `--trace` checks passed in Renode. Native probe-rs also flashed both trace ELFs and recovered their SRAM snapshots from the physical board. The physical captures passed the same timing assertions with clear CFSR and HFSR. STM32Cube recorded two 501 ms waits. FreeRTOS recorded its sender and receiver task switches and two queue deliveries 500 ms apart. Both physical Perfetto traces are under `.cache/verification/tband-hardware.VIxVrw/`. After capture, the normal Rust greeting was flashed and verified again.

Windows continued to enumerate ST-LINK and the mikroC dongle. The CODEGRIP USB scan completed with an empty device list. [Probe checks](mikroe.md#headless-probe-checks)

## Automated SWD traces and USART6 console

`uni-cli check stm32cube --trace --hardware-trace` and `uni-cli check freertos --trace --hardware-trace` passed with Windows probe-rs 0.32.0 and the ST-LINK in SWD mode. The CLI recovered 94 and 359 trace bytes from SRAM, respectively. Both hardware recordings passed the same assertions as the Renode runs and reported clear CFSR and HFSR. An occupied-lock test returned the probe-busy error before flashing or creating a snapshot.

`uni-cli check freertos-console --trace --hardware` passed the Renode protocol suite and the hardware boot check. OpenOCD and GDB matched the vectors, stepped into the application, and stopped at the ready-state watchpoint. USART6 had BRR `0x8b`, PC6 and PC7 in AF8, RX IRQ enabled, 17 ready-banner bytes transmitted, and clear fault registers. An external UART adapter is required to repeat the command input suite on the board.

| Renode scenario | Observed result |
| --- | --- |
| Fragmented `ping`, CRLF and LF, LED commands | Exact responses and PD7 high then low |
| Embedded CR, NUL, overlong and empty lines | Four `ERR malformed` responses |
| Unknown command and subsequent valid input | `ERR unknown` and successful recovery |
| Ten commands queued in one burst | Four replies, six discarded lines and successful recovery |
| Tonbandgeraet ISR-to-task measurements | 16 matched enqueue and dequeue sequences with zero dropped trace events |

The Renode TIM2 trace measured 81–82 µs for isolated commands and 388–402 µs for the burst. The assertions allow up to 500 µs and 1,500 µs, respectively. These values measure the virtual interval from successful ISR enqueue to task dequeue. The report includes `trace/latency.tsv`, the exact USART6 transcript, the injected scenario, raw and decoded traces, and `provenance.tsv` with firmware hashes and tool versions. [Reproduce the checks](../AGENT.MD#timing-captures-and-usart6-console)

## SEGGER SystemView and RTT

The Cortex-M7 demo used SEGGER SystemView at `92ca7a81` and RTT at `9106eaa3`. Renode verified the USART6 greeting, the exact RTT terminal greeting on channel 0, the Start and Stop commands on channel 1, and three PD7 markers in a 900 ms recording. The resulting 117-byte recording decoded into 10 events. Renode reported clear CFSR and HFSR.

On the physical UNI Clicker, Windows OpenOCD flashed and verified the same ELF with ST-LINK. It found the RTT control block using the ELF symbol and streamed channel 1 to the WSL Rust decoder. A two-second capture produced 147 bytes, 15 decoded events, and eight PD7 markers. Both captures showed 250 ms between markers and zero dropped events. The physical check also verified the 22-byte RTT terminal greeting from SRAM. [Reproduction commands and artifact paths](../AGENT.MD#systemview-and-rtt)
