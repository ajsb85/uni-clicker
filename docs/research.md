# Board and toolchain research

## Hardware mapping

The lab uses the UNI Clicker base board and the SiBRAIN STM32F746ZG card. The base-board and card schematics must be read together because the base board names connector nets while the card assigns them to MCU pins. [UNI Clicker schematic](https://download.mikroe.com/documents/add-on-boards/uni_clicker/UNI-clicker-schematic-web.pdf) · [SiBRAIN schematic](https://download.mikroe.com/examples/full-featured-boards/8th-generation/schematic/SiBRAIN/SiBRAIN-for-STM32F746ZG-Schematic.pdf)

| Signal | Card mapping | Use in the lab |
| --- | --- | --- |
| LED C, MB5-CS | PD7 | Output, toggled every 500 ms |
| USB/UART TX and J2.16 (MB5-TX) | PC6, USART6 AF8 | 3.3 V MCU TX at 115200 baud |
| USB/UART RX and J2.15 (MB5-RX) | PC7, USART6 AF8 | 3.3 V MCU RX |
| SWDIO | PA13 through the programming mux | SWD data |
| SWCLK | PA14 through the programming mux | SWD clock |
| NRST | MCU reset | Connect under reset |

To capture text on a physical UART, use a 3.3 V TTL serial adapter. Connect J2.16 (PC6/TX) to adapter RX and connect grounds. J2.15 (PC7/RX) is available if you add input. The board's USB data lines route separately to the USB peripheral, so a USB cable on that connector alone provides no USART6 serial terminal with these examples.

The UNI Clicker manual specifies SW1 in the ON/up position for a third-party programmer and OFF/down for CODEGRIP or mikroProg. The SWD header uses 1 for target reference, 2 for SWDIO, 4 for SWCLK, and 10 for reset, with ground on 3, 5, 7, and 9. Consult the connector orientation before wiring. [UNI Clicker manual, pages 8–9](https://download.mikroe.com/documents/manual/uni-clicker-manual.pdf)

The STM32F746ZG has 1 MiB of internal flash at `0x08000000`, and 320 KiB of contiguous address space across DTCM and system SRAM from `0x20000000`. The firmware uses this SRAM for stack and globals. DMA masters have their own access constraints, so larger experiments should place DMA buffers deliberately. The debugger can use the local STM32F746 SVD, RM0385, and PM0253 to decode I/O and core fault registers. [STM32F746ZG product documentation](https://www.st.com/en/microcontrollers-microprocessors/stm32f746zg.html) · [RM0385](https://www.st.com/resource/en/reference_manual/rm0385-stm32f75xxx-and-stm32f74xxx-advanced-armbased-32bit-mcus-stmicroelectronics.pdf)

## Local resources used

| Workspace resource | What it provided |
| --- | --- |
| `UNI-clicker-schematic-web.pdf`, `SiBRAIN-for-STM32F746ZG-Schematic.pdf`, `uni-clicker-manual.pdf` | Pin and programming-mux mapping |
| `DS_stm32f746zg.pdf`, `rm0385-*.pdf`, `pm0253-*.pdf`, `STM32F746.svd` | MCU memory, registers and exception state |
| `STM32CubeProgrammer/` | Windows programming CLI and SWD driver integration |
| `mikroProg Suite For ARM/`, `mikroprog-stm32-manual-v100.pdf` | Vendor programmer installation and connector reference |
| `stm32duino/Arduino_Core_STM32`, `BoardManagerFiles`, `Arduino_Tools`, `stm32_svd`, `CMake_workspace` | F746ZG board menu, variant and upload behavior, package metadata and example references |
| `stm32-rs/stm32f7xx-hal` and neighboring crates | HAL and peripheral access options for a larger Rust application |
| `swift-embedded-examples/stm32-blink` and `stm32-uart-echo` | Cortex-M7 and Embedded Swift integration patterns |
| `renode/` and `simulation-resources.txt` | STM32F746 model reference and emulator inventory |
| `MCU_CARDS*.xlsx`, BSDL and IBIS files | Card catalog, JTAG boundary scan and signal integrity resources |

The checked-out STM32duino core identified itself as `3.2.0-dev` at `8c9c375`. The reproducible CLI build uses Boards Manager release `3.1.0`. The generic F746ZG option provides the chip and memory configuration. The sketch selects its own PD7 LED and PC6/PC7 USART6 pins and keeps the 16 MHz HSI reset clock.

STM32CubeF7 is pinned at `767d083e` (v1.17.2) with the HAL and CMSIS Device submodules from that release. Swift uses an ELF object targeting `armv7em-none-none-eabi` and a small C register bridge for volatile MMIO and startup. The Swift example controls the message and heartbeat loop. The Rust example uses the hard-float Cortex-M7 Rust target and `cortex-m-rt` startup. [STM32CubeF7](https://github.com/STMicroelectronics/STM32CubeF7) · [STM32duino core](https://github.com/stm32duino/Arduino_Core_STM32) · [Embedded Swift examples](https://github.com/swiftlang/swift-embedded-examples)

## Headless tools

`uni-cli` provides one entry point for multiple build tools, ELF analysis, SWD probing and verified flashing, interactive debugging, and scripted hardware checks. OpenOCD serves GDB on loopback. In WSL, CubeProgrammer and OpenOCD can run on Windows with the probe still attached to Windows, while GDB and the build tools run on Linux.

The observed USB device presented as ST-LINK V2 (`0483:3748`, firmware `V2J40S0`). Windows had no separately identified mikroProg endpoint. The verified programming path is the ST-LINK interface observed by CubeProgrammer and OpenOCD. The board supports the vendor programmer through a different SW1 setting, which remains a separate path to validate.

Native Windows `probe-rs` was verified on the existing ST-LINK WinUSB connection. WSL launches the native flasher with an ELF path translated by `wslpath -w` and connects `rust-gdb` to the probe-rs GDB server over loopback. The general `uni-cli` hardware workflow uses CubeProgrammer and OpenOCD. [Arduino and native Rust verification](verification.md#arduino-and-native-rust-programming)

## probe-rs source checkouts

The organization inventory on 2026-11-20 had 38 public repositories. All were cloned under `$UNI_WINDOWS_ROOT/probe-rs` with `git clone --depth 1 --no-tags`. The 37 repositories with a HEAD expose one commit each. `probe-rs-ppa` is empty. Local receipts in `.cache/probe-rs-org/revisions.tsv` record each commit. [probe-rs organization](https://github.com/probe-rs)

| Checkout | Use on this bench |
| --- | --- |
| `probe-rs` at `187f19a8` | Source for the flasher, explicit chip selection, RTT runner, GDB server and DAP tooling. The installed Windows release 0.32.0 was verified for flashing and GDB. |
| `rtt-target` at `08309db5` | Add RTT or defmt output to a Rust firmware profile and receive it over SWD through `probe-rs run` or `attach`. The Cortex-M examples show the target-side setup. |
| `embedded-test` at `48fe6ecf` | Port `examples/stm32f767` to the F746ZG for board-side test cases. The runner flashes one ELF and selects each case through semihosting. |
| `probe-rs/probe-rs-rpc` and `probe-rs-rpc-client` | The upstream checkout contains a persistent hardware-service protocol and client with schema compatibility checks. Evaluate them together from the same revision for an agent-controlled debug session. The installed release supplies the verified CLI and GDB path. |
| `cmsis-pack-manager`, `flash-algorithm`, `flash-algorithm-template` | Inspect chip packs or build a custom flash algorithm when adding a target. The native probe-rs registry already includes the bench STM32F746ZG. |
| `hive` and `hive-software` | References for scaling hardware testing to a fixture with multiple boards and programmers. |

The standalone `cargo-flash`, `cargo-embed`, `target-gen`, and `probe-rs-rtt` repositories are archived. Use the commands shipped with the verified probe-rs release for this bench.

## Tonbandgeraet timing traces

The depth-one checkout at `$UNI_WINDOWS_ROOT/Tonbandgeraet` is at `73aa9e440e2c0d920f990932e282e329069f40b0`. Its C recorder supports a bounded SRAM snapshot and a streaming backend. The Rust converter reads the binary event format and emits JSON Lines or a Perfetto trace. Keep the firmware recorder and converter on the same revision because the upstream format can change. [Tonbandgeraet source](https://github.com/schilkp/Tonbandgeraet/tree/73aa9e440e2c0d920f990932e282e329069f40b0)

The working copy is staged on ext4 under the directory recorded in `.cache/tonbandgeraet-stage`. Its `src/FreeRTOS-Kernel` symlink uses the NECTO FreeRTOS 11.3.0 tree. All 77 upstream unit tests passed. The upstream bare-metal integration, POSIX FreeRTOS integration, and QEMU MPS2-AN385 Cortex-M3 FreeRTOS integration also passed. QEMU produced 3,617 FreeRTOS events and 23 FreeRTOS metadata records, including task and queue names. The stage contains `unit.log`, the three integration logs, and `freertos-{posix,qemu}.perfetto-trace`.

The UNI Clicker experiment copied the STM32Cube application into the stage's `uni-renode/` directory and added `tband_config.h` and `tband_port.h`. It timestamps events using the existing 1 ms SysTick, saves and restores PRIMASK in trace critical sections, and uses 256 bytes of metadata space and 512 bytes of snapshot space. At the end of the run, the sample copies the metadata followed by the events to `uni_trace_capture`. Its first 32-bit word holds the number of captured bytes. Renode's `dump_file` command reads the structure from SRAM using the address in the ELF. The staged `main.c` and `run.resc` show the complete experiment.

The Renode run recovered 141 trace bytes and retained both exact USART6 greetings. JSON assertions found two 501 ms delays and heartbeat values 1 and 2 at 501 ms and 1,002 ms, with clear CFSR and HFSR. The 1 ms clock captured heartbeat timing. The USART6 transmission markers fell in the same tick in the emulation. The experimental ELF used 5,764 bytes of text and 1,736 bytes of BSS, including the snapshot and export buffers. The F746ZG experiment was simulated.

```bash
stage=$(cat .cache/tonbandgeraet-stage)
CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0 \
  cargo build --locked --manifest-path "$stage/src/tools/Cargo.toml" \
  --target-dir "$stage/target" -p tband-cli --no-default-features
cli="$stage/target/debug/tband-cli"
trace="$stage/uni-renode/trace.bin"
"$cli" --Werror dump --mode bare-metal "$trace" > "$stage/uni-renode/events.jsonl"
"$cli" --Werror conv --mode bare-metal --output "$stage/uni-renode/uni.perfetto-trace" "$trace"
```

Use JSON assertions for interval lengths, marker order, and missing events in automation. Keep the Perfetto artifact for queue, task, or interrupt timeline inspection. A bounded snapshot lets the firmware finish recording before the debugger reads it, which keeps the UART available for the existing smoke test. The FreeRTOS integration examples provide the scheduler and resource hooks for a later F746ZG RTOS port.

The Renode model instantiates a Cortex-M7, flash, SRAM, NVIC, RCC, GPIO and USART6. It can validate the exact greeting bytes without hardware. USB, oscillator tolerances, the programming mux, signal quality and external serial wiring require physical observations. [Renode STM32F746 model](https://github.com/renode/renode/blob/master/platforms/cpus/stm32f746.repl)
