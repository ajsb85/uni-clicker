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

MicroPython passed HEX verification and reset at `0x0802011c` with MSP `0x2004fff8`. GDB stepped into the frozen `uni_hello.py` startup and inspected 38 bytes containing the complete CRLF greeting inside `uart_tx_data`. The backtrace included the bytecode interpreter and the `machine.UART.write` path. USART6 BRR was `0x3aa`, and CFSR and HFSR were zero. Renode captured both greetings and PD7 high, low, high. The physical board was left running this image after the test.

The .NET nanoFramework managed application built with Windows `dotnet.exe` and printed five greetings in the POSIX runtime pinned at `e903edb`. The compatible `mscorlib.pe` uses `NFMRK2` and native contract hash `0x532e6934`. [Managed build and runtime instructions](frameworks.md)

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
