# UNI Clicker STM32F746ZG lab

Hello World firmware and framework ports for the Mikroe UNI Clicker with the SiBRAIN STM32F746ZG card. The standard bench examples toggle LED C on PD7 every 500 ms and send a toolchain-specific greeting over USART6 at 115200 baud, 8N1. Their ELFs expose `uni_heartbeat` and `uni_tx_bytes` for hardware verification. The managed runtimes use their own deployment and debugger checks.

| Build | Firmware tools | Source |
| --- | --- | --- |
| `stm32cube` | ST STM32CubeF7 HAL, CMSIS and startup, GNU Arm Embedded | [C example](examples/stm32cube/main.c) |
| `arduino` | Arduino CLI and the STM32duino generic F746ZG core | [Sketch](examples/arduino/HelloUni/HelloUni.ino) |
| `rust` | Cargo, `cortex-m` and `cortex-m-rt` | [Rust example](examples/rust/src/main.rs) |
| `swift` | Embedded Swift, GNU Arm Embedded linker, ST CMSIS startup | [Swift example](examples/swift/Hello.swift) |
| `zig` | Zig and MicroZig STM32F746ZG port | [Zig example](examples/zig/) |
| `necto`, `necto-windows` | Installed mikroSDK and Arm GCC | [NECTO example](examples/necto/) |
| `freertos`, `freertos-console`, `threadx`, `libopencm3` | Cortex-M7 kernels, an interrupt-driven USART6 console, and a peripheral library | [Framework projects](examples/frameworks/) |
| `zephyr`, `riot`, `chibios`, `mbed-os`, `nuttx`, `micropython` | SDK and interpreter builds for the UNI Clicker | [Framework targets](docs/frameworks.md) |
| `nanoframework`, `nanoframework-native` | Windows .NET SDK, nanoBooter and nanoCLR | [Managed and native .NET builds](docs/frameworks.md#net-nanoframework) |
| `mikroc`, `mikroc-source-check` | Classic mikroC PRO for ARM and an independent GCC/CMSIS build | [mikroC example](examples/mikroc/) |
| `pio-arduino`, `pio-stm32cube`, `pio-cmsis`, `pio-libopencm3`, `pio-zephyr` | PlatformIO environments | [PlatformIO workflow](docs/platformio.md) |

## Build

On the original Windows 11 and WSL2 bench, run `source tools/bench-env.sh` first. It points to the existing downloads, SDKs and hardware tools described in [AGENT.MD](AGENT.MD).

Use Linux or WSL with Git, Make, GNU Arm Embedded GCC, binutils and newlib, Cargo and Rust, Arduino CLI, and an Embedded Swift-capable toolchain. The build was designed for a Linux-native checkout with Windows vendor tools callable from WSL.

```bash
make deps-stm32cube
rustup target add thumbv7em-none-eabihf
arduino-cli core install STMicroelectronics:stm32@3.1.0 \
  --additional-urls https://github.com/stm32duino/BoardManagerFiles/raw/main/package_stmicroelectronics_index.json
make all
```

`make all` builds the original four examples and the host CLI. The remaining profiles use individual Make targets and the SDK paths listed in the [Mikroe](docs/mikroe.md) and [framework](docs/frameworks.md) guides. Outputs are ELF with debug information, BIN, and Intel HEX under `build/<toolchain>/`. `STM32CUBE_F7` can point to a local STM32CubeF7 tree with CMSIS and HAL populated. `STM32_GCC`, `ARDUINO_CLI`, and `SWIFTC` select alternate tool installations.

## Run a firmware check

```bash
source tools/bench-env.sh
make cli
build/cli/debug/uni-cli check stm32cube
```

The command builds the profile, inspects its firmware image and runs the Renode smoke test. It prints the path to `report.tsv` under `.cache/verification/check.*` with each stage's status, elapsed time and log filename. A failed stage sets a nonzero exit status and skips the remaining tests. The adjacent `provenance.tsv` records the Git commit, tracked changes, ELF SHA-256 digests and tool versions. See `uni-cli help` for the supported profiles.

Add `--hardware` to flash the connected STM32F746ZG via ST-LINK after the simulation passes. This option writes the selected firmware and starts the OpenOCD and GDB verification. The run directory includes the programmer, server and debugger logs.

- `uni-cli check rust --hardware --programmer probe-rs` selects native probe-rs programming with readback and the standard OpenOCD debugger check.
- `uni-cli check stm32cube --trace` and `uni-cli check freertos --trace` add Tonbandgeraet timing assertions and save a Perfetto artifact.
- `uni-cli check stm32cube --hardware-trace` and `uni-cli check freertos --hardware-trace` program the trace ELF through probe-rs, then recover and validate the SRAM recording over SWD. The artifacts are in the report's `hardware-trace/` directory.
- `uni-cli check freertos-console --trace` tests USART6 commands, malformed input and queue saturation in Renode. It saves per-command IRQ-to-task measurements in `trace/latency.tsv`.
- `uni-cli check freertos-console --hardware-trace --uart COM7 --runs 3` drives the physical USART6 port and records an IRQ-to-task latency baseline using the selected Windows 3.3 V adapter.
- `uni-cli test rust --hardware` runs the separate embedded-test ELF and captures RTT messages.
- `uni-cli systemview` checks SEGGER SystemView recording and RTT terminal output in Renode. Add `--hardware` to flash and capture through ST-LINK and OpenOCD. [SystemView workflow](AGENT.MD#systemview-and-rtt)
- `uni-cli check nuttx --hardware` and `uni-cli check micropython --hardware` use runtime-specific debugger checks. MicroPython flashes the split Intel HEX.

Combine `--trace`, `--hardware-trace` and `--hardware` on STM32Cube or FreeRTOS to check the instrumented image in Renode and on the board, then program and verify the regular firmware. [Capture procedure and console commands](AGENT.MD#timing-captures-and-usart6-console)

GitHub Actions runs the Rust greeting, the three Tonbandgeraet checks, and the SystemView RTT check in Renode. It uploads the verification reports and simulation artifacts. [Firmware simulation workflow](.github/workflows/firmware.yml)

The `arduino-usb-cdc` example uses the UNI Clicker USB-C connector in device mode for a Windows virtual COM console. [USB-C wiring and verification](docs/usb-cdc.md)

## Flash and debug

```bash
make cli
cli=build/cli/debug/uni-cli
export CUBE_PROG=/path/to/STM32_Programmer_CLI
"$cli" build stm32cube
"$cli" analyze stm32cube
"$cli" probe
"$cli" flash stm32cube
```

The flash command uses SWD, programs at `0x08000000`, verifies the bytes, and resets the target. If you need the existing contents, read flash with CubeProgrammer before writing. For WSL with the probe owned by Windows, set `CUBE_PROG` to the mounted Windows `STM32_Programmer_CLI.exe`. The CLI translates the BIN path for Windows.

Start OpenOCD after the programmer finishes. For a Windows OpenOCD install, export `OPENOCD` as its mounted `openocd.exe` path and `OPENOCD_SCRIPTS` as its mounted scripts directory. From one terminal run `debug/start-openocd.sh`, then use a second terminal for GDB.

```bash
build/cli/debug/uni-cli verify stm32cube
build/cli/debug/uni-cli debug stm32cube
```

`verify` checks flash vectors, reset state, the application entry and fault registers. The standard profile also checks GPIO transitions and USART6 transmit completion. The `nanoframework-native` profile checks the nanoBooter reset and two managed greetings at nanoCLR's native output routine. The interactive command opens GDB with the matching ELF. The GDB client defaults to `gdb-multiarch` and the server to `localhost:3333`. Close OpenOCD before the next flash so CubeProgrammer can claim the probe.

For a serialized flash and GDB run with automatic probe-server cleanup, use `tools/verify-bench.sh stm32cube zig` after building those profiles. The NECTO Windows ST-LINK GDB server is available through `debug/start-st-gdbserver.sh`.

The bench also supports the native Arduino CLI SWD upload recipe with a Windows CubeProgrammer adapter and the native Windows probe-rs flasher and GDB server for Rust. [Arduino commands](AGENT.MD#arduino-cli-upload-and-debugger) · [Rust commands](AGENT.MD#native-rust-flashing-and-debugging)

## Simulate

With Renode on PATH, or `RENODE` set to its executable, run `tools/simulate.sh stm32cube`. The firmware profiles use the same offline Cortex-M7 model. The native .NET profile asserts the managed greeting at its nanoCLR dispatch point and captures binary Wire Protocol traffic from USART6.

Run `build/cli/debug/uni-cli simulate zephyr gpio` for the same simulation command through the Rust CLI. The CLI also accepts the `pio-` profiles and locates their PlatformIO-generated ELFs.

The [Renode guide](docs/renode.md) covers GPIO timing, boot traces, and GDB. The [framework guide](docs/frameworks.md) lists all twelve requested frameworks and runtimes, their integration commands, and verification status. See also the [board research](docs/research.md), [bench results](docs/verification.md), and [agent handoff](AGENT.MD).
