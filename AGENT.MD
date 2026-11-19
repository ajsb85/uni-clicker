# UNI Clicker bench handoff

## Start a fresh session

Use Bash under WSL2. The project files and Git history live on the Linux filesystem. The Windows workspace supplies the reference sources, vendor installations, and USB probe.

```bash
cd /home/gbast/uni-clicker
git status --short --branch
source tools/bench-env.sh
make cli
cli=build/cli/debug/uni-cli
```

The repository is [ajsb85/uni-clicker](https://github.com/ajsb85/uni-clicker). The mounted resource tree is `/mnt/c/Users/gbast/dev/uni-clicker` in WSL and `C:\Users\gbast\dev\uni-clicker` in Windows. The environment script accepts `UNI_WINDOWS_ROOT` and individual tool overrides. Check its exports and the installed paths before provisioning or searching for another copy.

Keep source and ordinary builds on the WSL filesystem. Keep capture files, SDK references, package caches, and scratch directories under `.cache/`. The large Windows-backed caches live under `$UNI_WINDOWS_ROOT/.uni-clicker-lab-cache`. Leave `/tmp` out of any command that needs to survive a session. Check `df -h . "$UNI_WINDOWS_ROOT"` before adding a new SDK or interpreter tree.

## Locate resources

Paths in the right column are relative to `$UNI_WINDOWS_ROOT` unless prefixed with `.cache/` or `/home/gbast/`.

| Need | Location |
| --- | --- |
| Baseboard connections, switches and debug header | `UNI-clicker-schematic-web.pdf`, `uni-clicker-manual.pdf`, `UNI_Clicker_2D_and_3D_files/` |
| MCU card connections and socket design | `SiBRAIN-for-STM32F746ZG-Schematic.pdf`, `sibrain-standard-guidelines-2021-10-6.pdf`, `MCU_CARDS*.xlsx` |
| Flash, UART, reset, GPIO and clocks | `DS_stm32f746zg.pdf`, `rm0385-*.pdf`, `STM32F746.svd`, `stm32f746.svd.patched`, `STM32F7_svd/` |
| Cortex-M7 faults, trace, boot ROM, cache and DMA | `pm0253-*.pdf`, `an4989-*.pdf`, `an2606-*.pdf`, `an4839-*.pdf`, `an4031-*.pdf`, `es0290-*.pdf` |
| JTAG boundary scan and electrical models | `CortexMx.bsd`, `STM32F745_746_750_756_LQFP144.bsd`, `stm32f745_746_756_lqfp144.ibs` |
| ST flashing and drivers | `STM32CubeProgrammer/bin/STM32_Programmer_CLI.exe`, `STM32CubeProgrammer/doc/`, `STM32CubeProgrammer/api/`, `st_link_USB_driver/` |
| STM32CubeF7 HAL, CMSIS and startup | `.cache/vendor/STM32CubeF7` at `767d083e`; run `make deps-stm32cube` to reconstruct it |
| Arduino source, variants, recipes and index | `stm32duino/Arduino_Core_STM32/`, `BoardManagerFiles/`, `Arduino_Tools/`, `stm32_svd/`, `CMake_workspace/` inside `stm32duino/` |
| Arduino build packages | `.cache/arduino-fast-data` has the F7 release files for STM32duino 3.1.0; `.uni-clicker-lab-cache/arduino-data` contains the full installed core and tools |
| Rust references | `stm32-rs/stm32f7xx-hal/` and adjacent PAC/HAL repositories; local target `thumbv7em-none-eabihf` |
| Swift examples and installed compiler | `swift-embedded-examples/stm32-{blink,uart-echo}/`, `.uni-clicker-lab-cache/swift/usr/bin/swiftc` |
| Zig and MicroZig | `zig` on WSL PATH, version 0.17.1; `microzig/` commit `f629434`; `port/stmicro/stm32/src/Chips.zig` has the F746ZG target |
| Vendor classic ARM compiler | `mikroC PRO for ARM/mikroCARM.exe`, `Defs/STM32F746ZG.c`, `Uses/`, `Examples/ST/`, `mikroc_PRO_ARM.chm` in that install |
| NECTO Studio and mikroSDK | `necto-studio/NECTOStudio/bin/NECTOStudio.exe`, `NECTOStudio7/templates/`, `NECTOStudio7/databases/necto_db.db`, `NECTOStudio7/packages/sdk/mikroSDK_v2/src` |
| NECTO GDB and ST tools | `NECTOStudio7/packages/debuggers/gdb/arm/bin/`, `NECTOStudio7/packages/st_tools/{cubeprogrammer,stlinkgdbserver}/tools/` |
| MikroE programmer and alternate debug backends | `mikroProg Suite For ARM/`, `mikroprog-stm32-manual-v100.pdf`, `CODEGRIP/CODEGRIP Suite/{CodegripCmd,CodegripGdbServer}.exe`, `NECTOStudio7/packages/programmers/{codegrip,segger}/` |
| Installer and bootloader packages | `mikroe-software/`, including the USB HID mikroBootloader manual; `mikroC PRO for PIC/` is for a different architecture |
| Renode and upstream examples | `.cache/tools/renode/renode` and `renode-test`; `renode/renode/{platforms,scripts,tests}`, `renode/renode-docs/source`, `renode/renode-infrastructure/`, `simulation-resources.txt` |
| Existing logs and original board flash | `.cache/verification/`, `.cache/sim/`, and private `.cache/pre-lab-flash.bin` |

The source table in [research](docs/research.md) records the relevant manuals and provenance. Use `pdftotext -layout` and `rg` to find pin or register details and reconcile the baseboard and card schematics. For legacy mikroC help, `7z x` can extract `mikroc_PRO_ARM.chm` to `.cache/docs/mikroc`. Its `command_line.htm` describes the compiler options.

## Board and verified Windows transport

| Setting | This bench |
| --- | --- |
| Target | Mikroe UNI Clicker and SiBRAIN STM32F746ZG, Cortex-M7 |
| Probe | ST-LINK V2, USB `0483:3748`, firmware `V2J40S0` |
| SWD identification | STM32 device group `0x449`, revision Z, 1 MiB of flash |
| Startup flash | `0x08000000`, Thumb reset vector in word 1 |
| RAM | DTCM starts at `0x20000000`; system SRAM starts at `0x20010000`; end `0x20050000` |
| Observable GPIO | LED C, PD7 through MB5-CS, active high |
| USART6 | PC6/TX at J2.16 and PC7/RX at J2.15, AF8, 115200 8N1 |
| Clock for the bare-metal examples | 16 MHz HSI; USART6 BRR `0x8b` with oversampling by 16 |

The validated probe is owned by Windows. WSL runs the build, ELF tools, and GDB. WSL invokes the Windows CubeProgrammer and OpenOCD executables directly. The working Windows-to-WSL GDB connection is `127.0.0.1:3333`.

```bash
powershell.exe -NoProfile -Command 'Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match "STLink|mikroProg|CODEGRIP|STM32" } | Select-Object Status,FriendlyName,InstanceId'
"$cli" probe
```

If the device is absent, check board power, the probe USB data cable, target reference, GND, SWDIO, SWCLK, NRST, and the switch. For ST-LINK, SW1 is ON/up. For a verified MikroE programmer with compatible cable, the manual specifies SW1 OFF/down. On J10, pins 1, 2, 4, and 10 are VTref, SWDIO, SWCLK, and reset. Pins 3, 5, 7, and 9 are GND. Keep the known working connection while diagnosing a software problem. An installed CODEGRIP or mikroProg application alone does not establish a separate probe connection.

Use a 3.3 V TTL adapter on J2.16 and a shared ground when the task requires a physical UART capture. A USART transmission-complete register check and an exact Renode transcript are useful separate evidence.

For vendor executables, use `wslpath -w` when passing an image or directory to Windows. Old compiler tools can require a real drive-letter working directory. Stage vendor compiler inputs under the Windows-backed cache. Keep the development copy under `/home/gbast/uni-clicker`.

## Develop, verify, and debug

1. Build the changed profile with `make <profile>`. Use `make all` for the standard compiler set and the individual targets for additional SDKs. Keep the ELF with debug information, BIN, and HEX from the same build. Use `arm-none-eabi-nm -n`, `readelf -l`, `objdump -dSl`, and `uni-cli analyze` before touching hardware.
2. Run `tools/simulate.sh <profile>` and the relevant [Renode scenario](docs/renode.md). The minimum hello firmware convention is the banner at boot and each second, PD7 transitions each 500 ms, and 32-bit `uni_heartbeat` and `uni_tx_bytes` symbols.
3. Keep one hardware owner. Stop any probe session before `"$cli" flash <profile>`. CubeProgrammer uses SWD connect-under-reset, verifies bytes, and resets the MCU. The original 1 MiB image is backed up locally. Retain the flash backup privately with any other bench-only evidence.
4. Run `debug/start-openocd.sh` in one terminal and `"$cli" verify <profile>` in another. For interactive work, use `"$cli" debug <profile>`. The batch check compares both vectors, checks reset PC/MSP/Thumb state, breaks and single-steps at the application entry, observes three hardware watchpoints, and checks GPIO routing, USART6, and fault registers.
5. To continue after a debugger stop, detach or resume the core. Check a heartbeat twice over CubeProgrammer hot-plug or read a physical terminal. Record the last active image and any differences between hardware and simulation in [verification](docs/verification.md).

For a hardware investigation, begin with these commands in the existing GDB session.

```gdb
monitor reset halt
maintenance flush register-cache
info registers pc msp xpsr
x/2wx 0x08000000
x/6i $pc
x/7wx 0xe000ed24
x/wx 0x40023844
x/wx 0x40020c14
x/wx 0x4001141c
```

At a fault, decode SHCSR, CFSR, HFSR, MMFAR and BFAR with RM0385 and PM0253. Save the fault status and exception stack frame before triggering another reset. Use `nm` addresses when GDB starts in a different language context. Use hardware breakpoints in flash and location watchpoints for state words. After `monitor reset halt`, flush the client register cache so GDB reads the new state.

For a source-level regression, keep a known-good ELF and binary, reduce the difference to one clock or peripheral, and compare equivalent instructions, register values and virtual time in Renode before repeating SWD tests. Include the ELF hash, exact compiler and SDK revision, simulator model, probe backend, flash report, and first failing observation in the notes. Use [the verified Renode recipes](docs/renode.md) for exact output, GPIO timing, instruction traces, and GDB.

## Work on a new peripheral

Start with the SiBRAIN mapping and check that the proposed pin is available on the installed baseboard. Locate the clock gate, clock source, control bits, IRQ number, and DMA reachability in RM0385. Add a short bounded simulation scenario with evidence of a successful operation and a failure or timeout path. For IRQ or DMA work, inspect vector registration, pending and enable bits, buffer alignment, and SRAM bank before enabling caches. Model additional peripherals in a focused REPL overlay and test that they respond through the intended bus. Validate timing, electrical behavior, and missing peripheral modes on the bench.

Choose the smallest useful test at each stage. Renode UART or GPIO smoke is fast and repeatable. Instruction tracing is useful for short boot or fault windows. SWD is the source of truth for the target wiring, actual boot, and real peripheral state. Freeze a successful test in a script or Robot suite when it becomes part of the routine.

## Updated NECTO installation and findings

NECTO Studio 7.4.4 is at `$UNI_WINDOWS_ROOT/necto-studio/NECTOStudio/bin/NECTOStudio.exe`. Its installed GCC at `NECTOStudio7/packages/compilers/gcc/arm/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe` reports xPack 14.2.1. The Windows CMake package is 3.30.5. The latest install added `packages/core` and `packages/preinit`. The mikroSDK source is `NECTOStudio7/packages/sdk/mikroSDK_v2/src`, including `targets/arm/mikroe/common/include/mcu_definitions/STM32/STM32F746ZGTx` and the corresponding `mcu_reg_addresses/STM32/STM32F746ZG`.

Windows GCC derives its tool search path from the working directory on this WSL setup. Change to the compiler's Windows `bin` folder before invoking it. From the wrong directory it reports `cannot execute 'cc1'` even though `libexec/gcc/arm-none-eabi/14.2.1/cc1.exe` exists. Run `make necto-windows` for the checked-in working procedure. Its BIN matched the Linux GCC `make necto` output exactly. The NECTO example uses the actual F7 mikroSDK GPIO implementation, plus ST CMSIS startup and USART6. The local F407 scratch SDK profile is useful for understanding layout. Select the F746ZG definitions for builds.

The ST-LINK server shipped by NECTO 7.4.4 was verified from WSL. Use `debug/start-st-gdbserver.sh` and `target remote 127.0.0.1:3335` in GDB. It can step the same running image at a C source line. Use OpenOCD on 3333 for the repo batch verifier. [Mikroe build and debugger details](docs/mikroe.md)

## Classic mikroC PRO for ARM

The Windows license dongle is HID `1011:0022`, bus description `mE Dongle mC ARM`. Keep it attached to Windows. Use **Help → License Activation** in the classic IDE for license status. Keep license values and serials out of logs and Git.

The elevated classic IDE built the staged `.mcpar` and recorded the working `mikroCARM.exe` invocation in `hello.log`. `make mikroc` now replays that exact argument format from WSL without elevation. It stages the application under `$UNI_WINDOWS_ROOT/.uni-clicker-lab-cache/mikroc/run.*`. The prior `error[340]` came from a different command line. Use Windows `ProcessStartInfo.Arguments`, a drive-letter working directory, a relative `hello.c`, trailing backslashes in the search paths, and the explicit `Uses\ST M7` library list in `tools/build-mikroc.ps1`. If the headless build fails, check the stage log and the dongle before changing compiler flags. If project options change, approve the normal UAC launch, open the staged `.mcpar` in the IDE, build, and compare the newly logged command.

```bash
make mikroc
"$cli" analyze mikroc
tools/simulate.sh mikroc
tools/simulate.sh mikroc gpio
tools/verify-bench.sh mikroc
```

The native HEX, BIN, ASM, LST, DBG and compiler log are in `build/mikroc/`. The generated ELF preserves the flashed bytes and adds application line mappings and symbols from the listing. The CLI verifies native startup at `0x080002c8`, MSP `0x2004fffc`, and breaks after vendor initialization at `mikroc_app_entry`. GDB stepped from `hello.c:32` to `hello.c:34` on the physical board. The listing derives source addresses and counter locations. Keep the vendor `.dbg` for the classic IDE, and use explicit memory types when reading the counters in GDB. The native image passed the exact USART6 and PD7 timing tests in Renode. The `mikroc-source-check` target independently builds the C source with GCC/CMSIS. [Reproduction and debugger notes](docs/mikroe.md)

## Frameworks and examples

| Framework | Location or build target | Established evidence |
| --- | --- | --- |
| STM32CubeF7 | `examples/stm32cube/`, `make stm32cube` | Flash, SWD, Renode |
| Arduino STM32duino | `examples/arduino/`, `make arduino` | Flash, SWD, Renode |
| Rust bare metal | `examples/rust/`, `make rust` | Flash, SWD, Renode |
| Embedded Swift | `examples/swift/`, `make swift` | Flash, SWD, Renode |
| Zig / MicroZig | `examples/zig/`, `make zig` | Flash, SWD, Renode |
| NECTO / mikroSDK | `examples/necto/`, `make necto necto-windows` | Flash, SWD, Renode and Windows compiler equivalence |
| Classic mikroC | `examples/mikroc/`, `make mikroc` and `make mikroc-source-check` | Matching IDE and headless native images, flash readback, SWD source stepping, Renode UART and GPIO, independent GCC/CMSIS check |
| FreeRTOS | `examples/frameworks/freertos/`, `make freertos` | Flash, SWD, Renode |
| Eclipse ThreadX | `examples/frameworks/threadx/`, `make threadx` | Flash, SWD, Renode |
| libopencm3 | `examples/frameworks/libopencm3/`, `make libopencm3` | Flash, SWD, Renode |
| Zephyr | `examples/frameworks/zephyr/`, Nucleo F746ZG overlay | App and upstream target |
| Apache NuttX | `examples/frameworks/nuttx/`, NSH app | App and upstream target |
| RIOT | `examples/frameworks/riot/`, Nucleo F746ZG | Cross-build at `2e1ced49`, native64 run, initial USART3 output in Renode |
| ChibiOS | `examples/frameworks/chibios/`, RT Nucleo F746ZG | App and upstream target |
| Mbed OS | `examples/frameworks/mbed-os/`, Nucleo F746ZG | App and upstream target |
| MicroPython | `examples/frameworks/micropython/`, staged F746ZG UART remap | App and tested board staging |
| .NET nanoFramework | `examples/frameworks/nanoframework/`, managed project | Source and project format |

See [framework build and port instructions](docs/frameworks.md) before flashing a reference board or interpreter. The verified RTOS kernels are the local NECTO FreeRTOS 11.3.0 and the ThreadX checkout at `$UNI_WINDOWS_ROOT/.uni-clicker-lab-cache/frameworks/threadx` (`b2868c3`). The libopencm3 checkout lives alongside it at `a3977e1`. Use the hard-float Cortex-M7 ABI for its F7 archive. Its framework library must be built before linking the example. Zephyr, NuttX, RIOT, ChibiOS, Mbed OS, MicroPython and nanoFramework retain their own build, runtime and board requirements.

Use `tools/verify-bench.sh zig necto-windows freertos threadx libopencm3` for a serialized hardware run after building those profiles. It retains separate ELF, programmer, server and GDB logs in one `.cache/verification/bench.*` directory. For MicroZig, keep the compiler's local build cache on WSL and the large source packages on the Windows mount. Moving the Zig build cache itself to the Windows filesystem caused executable cache rename failures. The build script remedies the Ubuntu multiarch include path when Zig's native `regz` dependencies need `asm/types.h`.

## Queued PlatformIO work

The PlatformIO references are cloned under `$UNI_WINDOWS_ROOT/platformio/`. The checked-out revisions are `platform-ststm32` at `c419cfe`, `platformio-core` at `d8c2135`, `platformio-docs` at `a6877ce`, and `platformio-vscode-ide` at `3af3881`. The WSL installer environment is `.cache/platformio-venv`. Start the PlatformIO examples after finishing the current MikroE work. Verify the `nucleo_f746zg` board metadata against the physical UNI Clicker pinout before any upload, and reuse the local Renode model and Windows SWD workflow.
