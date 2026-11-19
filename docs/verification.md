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

The classic mikroC compiler produced no HEX because it reported source-file error 340. The project, staging script, tested paths and remaining native-tool dependency are recorded in [Mikroe notes](mikroe.md). Reference framework and runtime projects have their own verification status in the [framework guide](frameworks.md).
