# Framework examples

The examples use the STM32F746ZG family and a greeting as the first observable operation. The bench-native builds use the UNI Clicker PD7 LED and USART6 PC6/PC7. The upstream board and runtime examples state which port they require. Keep their full framework flash layouts and clock trees separate from the bare-metal lab images.

| Framework or runtime | Application | Build or integration target | Bench status |
| --- | --- | --- | --- |
| STM32CubeF7 | [HAL/CMSIS hello](../examples/stm32cube/) | `make stm32cube` | Renode and physical SWD passed |
| Zephyr | [Application and board overlay](../examples/frameworks/zephyr/) | `nucleo_f746zg` with PC6/PC7 and PD7 remap | Source and upstream target checked |
| FreeRTOS | [Static task](../examples/frameworks/freertos/) | `make freertos` | Renode and physical SWD passed |
| Eclipse ThreadX | [Static thread and Cortex-M7 setup](../examples/frameworks/threadx/) | `make threadx` | Renode and physical SWD passed |
| Arduino STM32duino | [Sketch](../examples/arduino/HelloUni/) | `make arduino` | Renode and physical SWD passed |
| Apache NuttX | [NSH application](../examples/frameworks/nuttx/) | `stm32f746g-disco:nsh` reference port | Host greeting and upstream target checked |
| RIOT | [Application](../examples/frameworks/riot/) | `nucleo-f746zg` reference port | Cross-build, native64 run, first Renode banner |
| ChibiOS | [RT application](../examples/frameworks/chibios/) | `RT-STM32F746ZG-NUCLEO144` with USART6 enabled | Source and upstream target checked |
| libopencm3 | [Bare-metal application](../examples/frameworks/libopencm3/) | `make libopencm3` | Renode and physical SWD passed |
| Mbed OS | [CMake C++ application](../examples/frameworks/mbed-os/) | `NUCLEO_F746ZG`, archived 6.x toolchain | Source and upstream target checked |
| MicroPython | [Python application and board staging](../examples/frameworks/micropython/) | STM32 port with `NUCLEO_F746ZG` USART6 remap | Staging tested against upstream board header |
| .NET nanoFramework | [Managed project](../examples/frameworks/nanoframework/) | Compatible nanoCLR and Windows project system | Source and project format checked |

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

From an initialized Zephyr west workspace with its SDK and modules, run the following. The overlay moves the console to USART6 PC6/PC7, selects HSI, and adds PD7. Review the generated `zephyr.dts` and clocks for additional devices before flashing a new Zephyr revision. The app uses the Zephyr scheduler and GPIO APIs. [Zephyr](https://github.com/zephyrproject-rtos/zephyr)

```bash
lab=/home/gbast/uni-clicker
cd "$ZEPHYR_WORKSPACE"
west build -b nucleo_f746zg "$lab/examples/frameworks/zephyr" -d "$lab/build/zephyr"
```

## Apache NuttX

Use matching NuttX and NuttX Apps checkouts. Stage the application into a writable Apps checkout as `examples/uni_hello`. Configure `stm32f746g-disco:nsh`, enable `EXAMPLES_UNI_HELLO` under the examples menu, and build from the NuttX root. Run `unihello` at the NSH prompt. The application uses the configured NuttX console. The Discovery BSP needs board clock and console routing work before use on the UNI Clicker. [Apache NuttX](https://github.com/apache/nuttx) · [Apache NuttX Apps](https://github.com/apache/nuttx-apps)

```bash
lab=/home/gbast/uni-clicker
mkdir -p "$NUTTX_APPS/examples/uni_hello"
cp "$lab"/examples/frameworks/nuttx/{Kconfig,Make.defs,Makefile,unihello_main.c} \
   "$NUTTX_APPS/examples/uni_hello/"
cd "$NUTTX"
tools/configure.sh -a "$NUTTX_APPS" stm32f746g-disco:nsh
make menuconfig
make -j4
```

## RIOT

`make -C examples/frameworks/riot RIOTBASE="$RIOT" BOARD=nucleo-f746zg` builds against the official F746ZG Nucleo port. The app uses `ztimer_msec`, standard output, and the board LED. The ELF built at revision `2e1ced49` with GNU Arm GCC 14.2.1 using the local checkout under `.cache/vendor/RIOT`. The `native64` build emitted repeated greetings and LED events when run directly. The Nucleo ELF emitted its first greeting on USART3 in the full STM32F746 Renode model. Later delays exercised LPTIM1 registers that the model lacks, so the simulation establishes startup and first UART output. Adapt the RIOT BSP for USART6 and PD7 on the UNI Clicker. [RIOT](https://github.com/RIOT-OS/RIOT)

## ChibiOS

Use a scratch checkout of `demos/STM32/RT-STM32F746ZG-NUCLEO144`. Replace that demo's `main.c` with [this application's main](../examples/frameworks/chibios/main.c), enable `HAL_USE_SERIAL` and `STM32_SERIAL_USE_USART6` in the demo configuration, and run `make -j4` in the demo directory with GNU Arm tools. The source configures PC6/PC7 AF8 and PD7. Review the demo clock source for the SiBRAIN card when porting it. [ChibiOS](https://github.com/ChibiOS/ChibiOS)

## Mbed OS

Use the archived Mbed OS 6.x `NUCLEO_F746ZG` target and its matching GCC_ARM version. Stage the app or place the matching Mbed checkout under the app as `mbed-os/`. From the app run `mbed-tools configure -m NUCLEO_F746ZG -t GCC_ARM -o build`, then `cmake -S . -B build -G Ninja -DMBED_TARGET=NUCLEO_F746ZG -DMBED_TOOLCHAIN=GCC_ARM` and `cmake --build build`. Set `MBED_PATH` if the checkout is elsewhere. The app uses `BufferedSerial`, a GPIO and the RTOS sleep API. [Mbed OS](https://github.com/ARMmbed/mbed-os)

## MicroPython

Stage a new STM32 board directory outside the upstream checkout. The helper verifies and replaces the USART6 pin assignments in the F746ZG Nucleo header. Build the interpreter using MicroPython's documented STM32 prerequisites, including `mpy-cross` and required submodules. Once an appropriate STM32 port is running, deploy [main.py](../examples/frameworks/micropython/main.py) to its filesystem with `mpremote` or the board's storage interface. The application starts USART6 and drives PD7. Before flashing on SiBRAIN hardware, verify the cloned port's clock setup, storage regions and REPL transport. [MicroPython](https://github.com/micropython/micropython)

```bash
lab=/home/gbast/uni-clicker
board="$lab/.cache/micropython/UNI_CLICKER_F746ZG"
mkdir -p "$(dirname "$board")"
python3 "$lab/examples/frameworks/micropython/stage-board.py" "$MICROPYTHON" "$board"
make -C "$MICROPYTHON/mpy-cross" -j4
make -C "$MICROPYTHON/ports/stm32" BOARD=UNI_CLICKER_F746ZG BOARD_DIR="$board" \
    BUILD="$lab/build/micropython" -j4
```

## .NET nanoFramework

Open [UniClickerHello.nfproj](../examples/frameworks/nanoframework/UniClickerHello.nfproj) in Windows Visual Studio with the nanoFramework extension or use its MSBuild environment. In the project directory run `nuget restore packages.config -PackagesDirectory packages` and `MSBuild UniClickerHello.nfproj`. Deploy to a compatible nanoCLR device and read the Visual Studio debug output. The upstream interpreter provides a ChibiOS STM32F769I Discovery target. A F746ZG UNI Clicker CLR needs a separate runtime port and flash layout before the managed app can run on this board. [nanoFramework interpreter](https://github.com/nanoframework/nf-interpreter) · [nanoFramework samples](https://github.com/nanoframework/Samples)
