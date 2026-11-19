# UNI Clicker STM32F746ZG lab

Hello World firmware and framework ports for the Mikroe UNI Clicker with the SiBRAIN STM32F746ZG card. The verified bench builds toggle LED C on PD7 every 500 ms and sends a toolchain-specific greeting over USART6 at 115200 baud, 8N1. Their ELFs expose `uni_heartbeat` and `uni_tx_bytes` for hardware verification.

| Build | Firmware tools | Source |
| --- | --- | --- |
| `stm32cube` | ST STM32CubeF7 HAL, CMSIS and startup, GNU Arm Embedded | [C example](examples/stm32cube/main.c) |
| `arduino` | Arduino CLI and the STM32duino generic F746ZG core | [Sketch](examples/arduino/HelloUni/HelloUni.ino) |
| `rust` | Cargo, `cortex-m` and `cortex-m-rt` | [Rust example](examples/rust/src/main.rs) |
| `swift` | Embedded Swift, GNU Arm Embedded linker, ST CMSIS startup | [Swift example](examples/swift/Hello.swift) |
| `zig` | Zig and MicroZig STM32F746ZG port | [Zig example](examples/zig/) |
| `necto`, `necto-windows` | Installed mikroSDK and Arm GCC | [NECTO example](examples/necto/) |
| `freertos`, `threadx`, `libopencm3` | Upstream Cortex-M7 kernels and peripheral library | [Framework projects](examples/frameworks/) |
| `mikroc` | Classic mikroC PRO for ARM project and CLI reproduction | [mikroC example](examples/mikroc/) |

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

`verify` checks the flash vectors, reset state, entry breakpoint, an instruction step, three GPIO transitions, USART6 transmit completion, and fault registers. It resets and resumes the loaded firmware. The interactive command opens GDB with the matching ELF. The GDB client defaults to `gdb-multiarch` and the server to `localhost:3333`. Close OpenOCD before the next flash so CubeProgrammer can claim the probe.

For a serialized flash and GDB run with automatic probe-server cleanup, use `tools/verify-bench.sh stm32cube zig` after building those profiles. The NECTO Windows ST-LINK GDB server is available through `debug/start-st-gdbserver.sh`.

## Simulate

With Renode on PATH, or `RENODE` set to its executable, run `tools/simulate.sh stm32cube`. Substitute any of the other build names to compare the exact USART6 greeting in the same offline Cortex-M7 model.

The [Renode guide](docs/renode.md) covers GPIO timing, boot traces, and GDB. The [framework guide](docs/frameworks.md) lists all twelve requested frameworks and runtimes, their integration commands, and verification status. See also the [board research](docs/research.md), [bench results](docs/verification.md), and [agent handoff](AGENT.MD).
