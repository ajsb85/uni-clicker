# Framework examples

The examples use the STM32F746ZG family and a greeting as the first observable operation. The bench-native builds use the UNI Clicker PD7 LED and USART6 PC6/PC7. The upstream board and runtime examples state which port they require. Keep their full framework flash layouts and clock trees separate from the bare-metal lab images.

| Framework or runtime | Application | Build or integration target | Bench status |
| --- | --- | --- | --- |
| STM32CubeF7 | [HAL/CMSIS hello](../examples/stm32cube/) | `make stm32cube` | Renode and physical SWD passed |
| Zephyr | [Application and board overlay](../examples/frameworks/zephyr/) | `make zephyr` | Renode and physical SWD passed |
| FreeRTOS | [Static task](../examples/frameworks/freertos/) | `make freertos` | Renode and physical SWD passed |
| Eclipse ThreadX | [Static thread and Cortex-M7 setup](../examples/frameworks/threadx/) | `make threadx` | Renode and physical SWD passed |
| Arduino STM32duino | [Sketch](../examples/arduino/HelloUni/) | `make arduino` | Renode and physical SWD passed |
| Apache NuttX | [Startup greeting](../examples/frameworks/nuttx/) | `make nuttx` | Renode greeting, flash and physical source stepping |
| RIOT | [Application and UNI Clicker board](../examples/frameworks/riot/) | `make riot` | Renode and physical SWD passed |
| ChibiOS | [RT application](../examples/frameworks/chibios/) | `make chibios` | Renode and physical SWD passed |
| libopencm3 | [Bare-metal application](../examples/frameworks/libopencm3/) | `make libopencm3` | Renode and physical SWD passed |
| Mbed OS | [CMake C++ application](../examples/frameworks/mbed-os/) | `make mbed-os` | Renode and physical SWD passed |
| MicroPython | [Frozen Python application](../examples/frameworks/micropython/) | `make micropython` | Renode UART and GPIO, physical flash and VM-to-UART debugger trace |
| .NET nanoFramework | [Managed project and board patch](../examples/frameworks/nanoframework/) | `make nanoframework-native` | POSIX, native Renode, flash and physical managed-to-native debugger trace |

## Verified bench-native builds

```bash
source tools/bench-env.sh
make deps-stm32cube
make -C "$OPENCM3" TARGETS=stm32/f7 -j4
make -j4 freertos threadx libopencm3
for profile in freertos threadx libopencm3; do
    tools/simulate.sh "$profile"
done
tools/verify-bench.sh freertos threadx libopencm3
```

FreeRTOS uses the locally installed kernel under `NECTOStudio7/packages/freertos/freertos_1130`. Its Cortex-M7 port hooks SVC, PendSV and SysTick, and the application uses static task memory. ThreadX uses the Cortex-M7 GNU port with a 1 ms tick and one static thread. Its application does not allocate a byte pool. The libopencm3 example uses the upstream startup and GPIO/USART APIs. Both fetched checkouts are under `$UNI_WINDOWS_ROOT/.uni-clicker-lab-cache/frameworks/` on this bench. Set `FREERTOS_ROOT`, `THREADX_ROOT`, or `OPENCM3` to use a different checkout. [FreeRTOS Kernel](https://github.com/FreeRTOS/FreeRTOS-Kernel) · [Eclipse ThreadX](https://github.com/eclipse-threadx/threadx) · [libopencm3](https://github.com/libopencm3/libopencm3)

The minimal Renode platform runs the scheduler and UART for these applications. Debug scheduler startup by breaking at `main`, then at the application's `greet` task or thread and the SysTick handler. Inspect PendSV registration, interrupt priorities and the process stack if a kernel starts and the first greeting never appears.

## Zephyr

The tested standalone build uses Zephyr 4.2.1, the `cmsis`, `cmsis_6`, and `hal_stm32` revisions in its `west.yml`, and GNU Arm Embedded GCC 14.2.1. The bench environment points to the extracted workspace. The overlay selects 16 MHz HSI, disables USART3, assigns USART6 to PC6/PC7 and adds PD7. The app uses Zephyr GPIO, UART and scheduler APIs. Check the generated `zephyr.dts` before changing board configuration. [Zephyr](https://github.com/zephyrproject-rtos/zephyr)

```bash
source tools/bench-env.sh
make zephyr
tools/simulate.sh zephyr
tools/verify-bench.sh zephyr
```

## Apache NuttX

Use matching NuttX and NuttX Apps `12.11.0` in a dedicated writable workspace. `make nuttx` stages the app as `examples/uni_hello`, configures the Nucleo F746ZG NSH base, then selects `unihello_main` as the startup task. It adjusts the scratch BSP to use the HSI-fed 216 MHz PLL and USART6 PC6/PC7. A regular NSH build can also run `unihello` as a built-in. The bench uses `kconfig-frontends-nox` extracted to `.cache/kconfig-frontends`. [Apache NuttX](https://github.com/apache/nuttx) · [Apache NuttX Apps](https://github.com/apache/nuttx-apps)

```bash
source tools/bench-env.sh
make nuttx
tools/simulate.sh nuttx
```

## RIOT

`make riot` uses the external `uni-clicker-f746zg` board at RIOT revision `2e1ced49`. It uses HSI, PD7, USART6 and the standard `ztimer_msec` API with TIM2. The original Nucleo reference used USART3 and LPTIM1. The new board gives Renode repeatable timer interrupts and the same UART and GPIO as the hardware. Add `.cache/vendor/RIOT` as a GDB source directory when stepping into RIOT kernel files. [RIOT](https://github.com/RIOT-OS/RIOT)

## ChibiOS

`make chibios` stages the RT Nucleo F746ZG demo from stable 21.11 revision `e209b17c`, selects HSI and SysTick, and uses a minimal board initializer for the UNI Clicker. The ChibiOS serial driver clears the USART transmit-complete flag in its interrupt handler. The application waits for `CHN_TRANSMISSION_END` before updating its counter. The reset code executes from the F746 ITCM flash alias `0x00200000`. CubeProgrammer still writes the physical flash at `0x08000000`. [ChibiOS](https://github.com/ChibiOS/ChibiOS)

## Mbed OS

`make mbed-os` builds archived Mbed OS 6.17.0 using the `NUCLEO_F746ZG` target, GNU Arm GCC 14.2.1 and the `mbed-tools` installed alongside `FRAMEWORK_PYTHON`. The app config selects the HSI-fed PLL and the TIM5 microsecond ticker for tickless RTOS sleep. The original LPTIM1 clock path stalled in the Renode model. The example uses `BufferedSerial`, PD7 and the CMSIS-RTX sleep API. [Mbed OS](https://github.com/ARMmbed/mbed-os)

## MicroPython

`make micropython` builds a native `mpy-cross` and a MicroPython 1.25.0 STM32 interpreter with the app frozen into it. The stage helper selects HSI, routes USART6 to PC6/PC7, and adds PD7 to the generated board pin table. The frozen profile disables USB, Ethernet, the internal flash filesystem and the Nucleo PC13 boot switch. The inherited switch stalled the physical board in `boardctrl.c` until it was disabled. Use the Intel HEX from `build/micropython/firmware/` for the split STM32 flash layout. The vectors are at `0x08000000` and text starts at `0x08020000`. [MicroPython](https://github.com/micropython/micropython)

```bash
source tools/bench-env.sh
make micropython
tools/simulate.sh micropython
```

## .NET nanoFramework

`make nanoframework` builds the SDK-style project with Windows `dotnet.exe` and exports `mscorlib.pe` and `UniClickerHello.pe` to `build/nanoframework/`. The legacy `.nfproj` can also be opened in Visual Studio with the nanoFramework extension. The SDK-style build uses `nanoFramework.NET.Sdk` 1.0.0 and CoreLibrary `2.0.0-preview.67`. Use the matching interpreter revision `e903edbe5258e8c6887c91c448ea5a0305e7040f` for the verified POSIX run. Its `NFMRK2` loader and native contract hash `0x532e6934` match the package. A newer runtime rejected the string table or native contract. [nanoFramework interpreter](https://github.com/nanoframework/nf-interpreter)

```bash
source tools/bench-env.sh
make nanoframework
clr=.cache/sdk-native/work/nano-posix-e903edb/bin/nanoFramework.nanoCLR.test
timeout 5s stdbuf -oL "$clr" build/nanoframework/mscorlib.pe build/nanoframework/UniClickerHello.pe
```

The command runs the repeating greeting for five seconds on the host. The CLR can be rebuilt from that revision with `cmake -S targets/posix -B build/posix -G Ninja -DNANO_POSIX_ENABLE_SMOKE=ON` followed by `cmake --build build/posix`.

### Native UNI Clicker image

`make nanoframework-native` builds the managed project and stages an independent UNI Clicker variant of the community `ChibiOS/ST_NUCLEO144_F746ZG` board. The variant uses 16 MHz HSI, the LSI RTC, 1 kHz SysTick, PD7, and SD6 on PC6/PC7 at 115200 baud. It removes the Nucleo PC13 user-button boot gate, reserves USART6 for the Wire Protocol transport and disables the inherited Ethernet and SNTP configuration. [nanoFramework community targets](https://github.com/nanoframework/nf-Community-Targets)

| Local input | Bench location relative to the repository | Override |
| --- | --- | --- |
| nanoCLR `e903edbe5258e8c6887c91c448ea5a0305e7040f` | `.cache/sdk-native/nano-e903edb` | `NANO_SOURCE` |
| Community targets `21b7f0bbe310e8c1487bcca41bfa6a7ee730fac0` | `.cache/sdk-native/nano-community` | `NANO_COMMUNITY` |
| ChibiOS stable 21.11, `074da4914767445cedff6b3ec4c13b58e6c1d5ab` | `.cache/sdk-native/work/nano-f746/_deps/chibios-src` | `NANO_CHIBIOS` |
| Mbed TLS 3.6.7, `068ff080b369adfac81509f9b57b2afabaf82dc5` | `.cache/sdk-native/work/nano-posix-v2/_deps/mbedtls-src` | `NANO_MBEDTLS` |

Use GNU Arm GCC 14.2.1, CMake, Ninja and the `FRAMEWORK_PYTHON` environment with `kconfiglib`. Remount the workspace SDK cache after a WSL restart. The runtime can be extracted from `nf-interpreter-e903edb.tar.gz` in the Windows framework cache. The native build goes under `.cache/sdk-native/work/nanoframework-native`. To configure against different dependencies, give `NANO_NATIVE_BUILD_DIR` a fresh directory so CMake resolves the new configuration. [Workspace setup](../AGENT.MD#start-a-fresh-session)

The combined BIN writes nanoBooter at `0x08000000`, nanoCLR at `0x08010000`, and `mscorlib.pe` followed by `UniClickerHello.pe` at `0x080c0000`. Gaps and the deployment end marker are erased bytes `0xff`. The ELFs execute through the ITCM alias. Keep both ELFs with the BIN to resolve addresses in the booter and the CLR.

```bash
source tools/bench-env.sh
make nanoframework-native cli
cli=build/cli/debug/uni-cli
"$cli" analyze nanoframework-native
"$cli" simulate nanoframework-native
"$cli" flash nanoframework-native
```

Start `debug/start-openocd.sh` in another terminal after CubeProgrammer releases the probe. Then run `"$cli" verify nanoframework-native`. The check resets to nanoBooter, stops twice at the native `CLR_Debug::Emit` entry, reads the C# string in memory, checks the CLR vector base and USART6 divisor, and steps an instruction. The CLR debug string is carried through the nanoFramework Wire Protocol. To inspect the CLR manually, use `"$cli" debug nanoframework-native` and load `build/nanoframework/nanoBooter.elf` to inspect booter symbols. [Simulation and debugging](renode.md#nanoframework-boot-and-managed-output)
