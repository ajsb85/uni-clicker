# NECTO and mikroC on Windows 11

## Installed resources

NECTO Studio 7.4.4 is installed at `$UNI_WINDOWS_ROOT/necto-studio/NECTOStudio/bin/NECTOStudio.exe`. Its workspace resources are under `$UNI_WINDOWS_ROOT/NECTOStudio7`.

| Resource | Path relative to `NECTOStudio7` |
| --- | --- |
| Arm GCC 14.2.1 | `packages/compilers/gcc/arm/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe` |
| CMake 3.30.5 | `packages/CMake/bin/cmake.exe` |
| mikroSDK 2.20.3 source | `packages/sdk/mikroSDK_v2/src` |
| Core and pre-init packages | `packages/core`, `packages/preinit` |
| ST-LINK GDB server 6.1.0 | `packages/st_tools/stlinkgdbserver/tools/bin/ST-LINK_gdbserver.exe` |
| ST programmer and Arm GDB | `packages/st_tools/cubeprogrammer/tools/bin/`, `packages/debuggers/gdb/arm/bin/` |
| Definitions and IDE templates | `databases/necto_db.db`, `templates/project_templates/`, `templates/toolchain_templates/` |

The database identifies the UNI Clicker, the SiBRAIN STM32F746ZG card, and the Cortex-M7 target. Its scratch `resources/__temp_setup_for_planet_debug__` was configured for STM32F407ZG. Use the F746ZGTx headers in the SDK source for this card.

## The tested mikroSDK example

```bash
source tools/bench-env.sh
make necto
tools/simulate.sh necto
tools/verify-bench.sh necto
make necto-windows
tools/simulate.sh necto-windows
tools/verify-bench.sh necto-windows
```

The app compiles the installed mikroSDK STM32 GPIO port implementation to configure PD7. The CMake project generates the SDK's flattening and core-header glue for the F746ZG, uses the ST CMSIS reset and USART6 registers, and holds the clock at HSI so it works with the model and physical card. Use the CLI CMake profile for repeatable development. The Windows profile compiles the same sources with NECTO's Arm GCC. The physical test and Renode transcript validate the resulting firmware.

When calling the Windows GNU driver from WSL, start it from its own Windows `bin` directory. Calling the mounted executable with a Linux working directory caused its program search path to start under the WSL project and reported `cannot execute 'cc1'`. Check `-print-prog-name=cc1` from the correct directory. [Windows build script](../tools/build-necto-windows.sh)

For the official ST debug backend, close OpenOCD and run the following on the flashed NECTO image.

```bash
source tools/bench-env.sh
debug/start-st-gdbserver.sh
```

```bash
gdb-multiarch -q -nx build/necto/hello.elf -ex 'target remote 127.0.0.1:3335'
```

```gdb
monitor help
info registers pc msp
x/2wx 0x08000000
stepi
info line *$pc
detach
```

ST GDB server commands include `monitor reset` and `monitor halt`. The OpenOCD batch verifier uses `monitor reset halt`, so use OpenOCD for that automated check. If Windows GCC embeds UNC paths, use GDB `set substitute-path` with the prefix shown by `wslpath -m "$PWD"` and the matching Linux checkout path. The tested ST-LINK GDB server attached, read both vectors, and stepped the NECTO firmware at its C source line.

## Classic mikroC PRO for ARM

[The example](../examples/mikroc/) contains a native `.mcpar` project for the STM32F746ZG at 16 MHz and a C source using the compiler's register names. Windows enumerates the ARM compiler key as HID `1011:0022`, bus description `mE Dongle mC ARM`. Leave the key on Windows. See **Software Activation** in the installed `mikroc_PRO_ARM.chm` and **Help → License Activation** in the IDE for license status.

```bash
source tools/bench-env.sh
make mikroc
tools/simulate.sh mikroc
tools/simulate.sh mikroc gpio
tools/verify-bench.sh mikroc
```

The successful IDE build uses **Open Project** (`Ctrl+Shift+O`) and **Build** (`Ctrl+F9`) in `mikroC PRO for ARM/mikroC Pro ARM.exe`. Approve the normal Windows UAC prompt when launching it from WSL. Open the staged `.mcpar` on a Windows drive. The IDE writes the compiler invocation to `hello.log` beside the project. Preserve this line when changing the target's settings or libraries.

The first standalone command reported `error[340]` for a source file that Windows could read. The working headless build replays the IDE's raw argument string through Windows `ProcessStartInfo` with a drive-letter working directory. It passes `hello.c` as a project-relative input, preserves the trailing backslashes on `-SP` and `-IP` directories, and lists the `Uses\ST M7` libraries explicitly. [Windows invocation](../tools/build-mikroc.ps1)

Each attempt stages CRLF copies under `$UNI_WINDOWS_ROOT/.uni-clicker-lab-cache/mikroc/run.*`. The wrapper requires fresh native outputs because `mikroCARM.exe` can return zero after an error. Successful runs copy the BIN, HEX, ASM, LST, DBG and `compiler.log` to `build/mikroc/`. The WSL build ran with no UAC prompt and its HEX matched the elevated IDE's output byte for byte.

`hello.elf` wraps the native flash bytes and uses the vendor listing to map GDB source lines and symbols. The build checks the BIN against the HEX and the listing opcodes, then checks the ELF's flash bytes again. Use `hello.dbg` with the vendor IDE. GDB has the source line table, routine labels, and the two counter addresses. Full C variable type information and frame unwinding are outside that listing-derived data.

```bash
# Start OpenOCD in a separate terminal after flashing.
build/cli/debug/uni-cli debug mikroc
```

```gdb
monitor reset halt
maintenance flush register-cache
x/3i $pc
hbreak hello.c:32
continue
stepi
info line *$pc
watch -l *(unsigned int *)&uni_heartbeat
continue
```

The vendor reset vector enters `main` at `0x080002c8` with MSP `0x2004fffc`. The first instruction adjusts SP by four bytes before calling the startup helpers. `mikroc_app_entry` is the first listed source address after the startup calls, `0x080002d2` in the tested build. The Rust CLI accepts the native image's word-aligned reset MSP. Use the listing and ELF from the current build when setting breakpoints or reading counters. [Physical and simulator results](verification.md)

The GCC/CMSIS source check maps the same C file's vendor register names to CMSIS lvalues. Use `make mikroc-source-check`, `tools/simulate.sh mikroc-source-check`, and `tools/verify-bench.sh mikroc-source-check` to reproduce that independent build. NECTO's database also lists **mikroC AI for ARM**. The local compiler package used by NECTO was GCC for ARM.

The native image was flashed and debugged through the detected ST-LINK V2. The installed CODEGRIP and classic mikroProg utilities remain available for a separate probe check.
