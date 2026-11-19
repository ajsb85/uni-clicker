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

[The example](../examples/mikroc/) contains a native `.mcpar` project and a C source using the compiler's STM32F746ZG register names. `make mikroc` stages the inputs on the Windows filesystem and invokes the installed `mikroCARM.exe` with listing, debug and BIN output enabled. The run log is `build/mikroc/compiler.log`. The wrapper checks that a HEX image was actually generated because this executable can return exit status zero after reporting errors.

The classic standalone compiler reported `error[340]` for the source path even though Windows could read the file. Tests with a drive-letter working directory, absolute and relative inputs, vendor search paths, and a short path did not produce a HEX image. A native mikroC flash or debug session remains unverified. The installed NECTO compiler package at the time of testing was GCC for ARM. The NECTO database also lists **mikroC AI for ARM**. If that package is available, try it in a NECTO project with the F746ZG card and preserve the compiler log and symbol output. The legacy ARM install, the NECTO compiler package, and the IDE plugin are separate resources.

Windows enumerates the attached ARM compiler key as the HID device `1011:0022` with bus description `mE Dongle mC ARM`. Keep the license dongle on Windows along with the ST-LINK. The local CHM's **Software Activation** topic describes automatic USB-dongle licensing. **Help → License Activation** in the vendor IDE is the place to confirm that the IDE recognizes the key. Opening this legacy IDE from an unelevated WSL-launched Windows process requires a normal Windows UAC approval. The last elevated launch was canceled before opening the staged project. USB enumeration confirms the key is present. The classic compiler's source-file error is a separate unresolved build observation.

The GCC/CMSIS source check builds the same `hello.c` with its vendor register names mapped to CMSIS lvalues. This image passed Renode and the full physical SWD checks. Use `make mikroc-source-check`, `tools/simulate.sh mikroc-source-check`, and `tools/verify-bench.sh mikroc-source-check` to reproduce it. The native `make mikroc` target continues to call mikroC's own compiler.

The programmer list on this bench showed ST-LINK V2. CODEGRIP and classic mikroProg software are installed for future probe validation.
