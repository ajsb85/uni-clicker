# PlatformIO on the UNI Clicker

The project in [`examples/platformio`](../examples/platformio/) uses PlatformIO ST STM32 `20.0.0` and the `nucleo_f746zg` metadata for the Cortex-M7, 1 MiB flash and 320 KiB RAM. Each application uses the UNI Clicker LED C on PD7 and USART6 on PC6/PC7 at 115200 8N1. The Arduino environment keeps the system on the 16 MHz reset clock through its `SystemClock_Config` override. The Zephyr overlay selects HSI and disables the Nucleo USART3 console.

```bash
source tools/bench-env.sh
make pio-arduino pio-stm32cube pio-cmsis pio-libopencm3 pio-zephyr
"$PLATFORMIO" run -d examples/platformio -e arduino -t renode
```

The native tools and the PlatformIO examples share application sources. PlatformIO supplies its own framework packaging, startup files and linker scripts. The project `west.yml` pins the CMSIS and STM32 module revisions from PlatformIO's Zephyr 4.4.2 manifest and limits installation to the modules used by this target. If a download is interrupted, check for `zephyr/module.yml` in that module's directory before retrying. An incomplete directory can cause the package installer to skip it. Move the incomplete directory out of the framework's `_pio/modules` tree and rerun the same environment.

The PlatformIO Zephyr overlay disables the unused backup SRAM. Zephyr 4.4.2 otherwise waits for the backup regulator ready bit during initialization, which the Renode power model does not implement. The five environments passed the PlatformIO `renode` target and physical SWD verification. [Bench measurements](verification.md)

The Core venv is `.cache/platformio-venv`. When the Linux workspace cache is mounted, the Core package directory is `.cache/sdk-native/platformio-core`. The four reference checkouts remain under `$UNI_WINDOWS_ROOT/platformio/`. [Bench paths and remount procedure](../AGENT.MD)

## Headless debug and simulation

```bash
make cli
cli=build/cli/debug/uni-cli
"$cli" analyze pio-cmsis
"$cli" simulate pio-cmsis gpio
"$cli" simulate pio-arduino trace
tools/verify-bench.sh pio-cmsis
```

The `renode` target builds the selected environment and passes its `firmware.elf` to the workspace simulation. The Rust CLI can run the same ELF under GDB, generate the startup trace, and assert the GPIO sequence. The default artifact path is `examples/platformio/.pio/build/<environment>/firmware.elf`. Set `PLATFORMIO_BUILD_DIR` to an absolute directory when sharing the build cache. Use a matching `.bin` for SWD programming.

The PlatformIO upload and debug metadata names ST-LINK. On this bench Windows owns the USB device. `uni-cli flash pio-<framework>` invokes Windows CubeProgrammer. `debug/start-openocd.sh` opens the Windows OpenOCD GDB server on port 3333. Connect with `uni-cli debug pio-<framework>` or use `tools/verify-bench.sh` to flash and verify in one run. [Windows probe setup](../AGENT.MD)
