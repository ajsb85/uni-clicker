# NECTO Click drivers on the UNI Clicker

The Click checker builds firmware for the STM32F746ZG SiBRAIN card and runs the ELF in Renode. Pass `--renode` to use the portable executable or use the default Rust host, which loads `librenode.so`. Each case registers its external device on a UNI Clicker REPL and defines bounded Monitor commands and expected USART6 output. [Case runner](../tools/check-necto-clicks.py) · [Embedded Renode host](../tools/uni-cli/src/renode_native.rs)

## Two-Wire ETH Click on MikroBUS 1

The parts are the UNI Clicker, STM32F746ZG SiBRAIN card, and Two-Wire ETH Click (MIKROE-5543). The UNI Clicker and SiBRAIN schematics map the socket as follows.

| MikroBUS 1 signal | F746 pin | Function in the probe |
| --- | --- | --- |
| CS | PA4 | Active-low software chip select |
| SCK | PA5 | SPI1 AF5 |
| CIPO / MISO | PA6 | SPI1 AF5 |
| COPI / MOSI | PB5 | SPI1 AF5 |
| RST | PE11 | Active-low reset request through the Click's reset supervisor |
| INT | PD3 | Active-low LAN8651 IRQ |
| SCL / SDA | PB8 / PB9 | I2C1 AF4 for the separate board EEPROM |

The vendor product page points to Microchip's OA-TC6 library. The pinned mikroSDK Click corpus has no Two-Wire ETH example. The project supplies a NECTO-compatible probe that uses the installed mikroSDK SPI and GPIO layers. The portable launcher compiles the SPI model when it includes the C# file and connects it to SPI1, CS, reset, and IRQ through the REPL. The probe uses a 64-byte empty data exchange for the status footer. A control write clearing `RESETC` leaves IRQ asserted until that exchange. [Firmware](../examples/necto-click/lan8651.c) · [Model](../sim/clicks/LAN8651Control.cs) · [Wiring](../sim/clicks/lan8651.repl)

The test checks OA version 1.1, the attached chip's ID `0x00086511`, the protected control complement, the `RESETC` write-one-to-clear behavior, IRQ acknowledgment, and software reset. The observed footer was `0x0000003E`. The unplugged case requires the firmware to reject a missing device. The model covers control transactions and the empty status exchange. Frame transfer on the 10BASE-T1S pair, PLCA, ClickID, EEPROM behavior, and electrical timing are outside this test.

On the WSL bench, run the NECTO compiler and simulation first. The `--flash` command temporarily programs the attached board, reads the result structure over ST-LINK, and restores and verifies the original 1 MiB flash.

```bash
source tools/bench-env.sh
tools/check-necto-clicks.py verify --case lan8651 --compiler necto
tools/check-lan8651-bench.sh --flash
tools/check-necto-clicks.py compare-lan8651 \
  .cache/verification/clicks.necto.RUN/lan8651 \
  .cache/verification/lan8651-bench.RUN
```

Use the directories printed by the first two commands. The comparison requires the same ELF SHA-256 and matches Renode's USART6 output against the values read from real MCU SRAM. The bench uses NECTO's xPack Arm GNU compiler. Linux GNU is the compiler used by CI.

## Thermo 28 reference case

This case compiles MikroE's original Thermo 28 `main.c` and AS6221 driver. The local board adapter supplies the MikroBUS 1 pin map, HSI timing, CMSIS startup, and USART6 logging. The external AS6221 attaches to I2C1 at its default address `0x48`. The case injects `22.50 °C` and `−5.25 °C`, then boots again with the Click removed and checks the diagnostic. The SDK's legacy 32-bit handle and GPIO conversions are compiler warnings in this build. [Board adapter](../examples/necto-click/) · [Case](../sim/clicks/thermo28.json)

## Ambient voltage sweep

The upstream Ambient example reads MikroBUS socket 1 AN on PA3 using ADC1
channel 3. The platform uses a 3.3 V reference and the example selects
12-bit resolution. The test sets channel 4 to full scale as a control for
channel selection, then sweeps channel 3 and checks the ADC data register
and USART6 output.

| Input | Raw ADC code | Reported light intensity |
| --- | ---: | ---: |
| 0.33 V | 409 | 47 µW/cm² |
| 1.65 V | 2047 | 235 µW/cm² |
| 2.97 V | 3685 | 424 µW/cm² |

These values exercise the SDK conversion from ADC code to light intensity.
The test uses an ideal voltage source and a fixed conversion time.
[Case](../sim/clicks/ambient.json) · [Wiring](../sim/clicks/ambient.repl) · [ADC model](../sim/nucleo-f746zg/F746VoltageADC.cs)

## SDK build gate

`tools/build-click-sdk.py` compiles the original SDK driver sources and
`example/main.c` separately, then links them with the UNI Clicker board
adapter and STM32F746ZG startup. Its USB log adapter routes the vendor example
messages to USART6. The first cohort covers Thermo 28 (I²C), Gyro 7 (SPI),
GPS (USART1), Ambient (ADC), Buzz (PWM), and Accel 21 (I²C plus SPI). It uses
the MikroBUS socket 1 pin map. ADC, PWM and UART use PA3, PD12, and PB7/PB6,
respectively, on this SiBRAIN card. [Cohort](../examples/necto-click/cohort.json) · [Pin map](../examples/necto-click/board.h)

```bash
make deps-stm32cube
tools/prepare-necto-clicks.sh
tools/build-click-sdk.py --out build/click-cohort/gcc
tools/check-necto-clicks.py verify --renode .cache/tools/renode/renode \
  --build-index build/click-cohort/gcc/build-index.json
```

For the installed NECTO xPack compiler under WSL, source
`tools/bench-env.sh` and build with `--compiler necto --out build/click-cohort/necto`.
The default Linux lane uses the prepared SDK and Arm GNU compiler.
Use repeatable `--case` arguments to add individual boards or `--all`
with `--shard` and `--shards` for the full SDK checkout. Missing source
files, socket mappings, or platform modules have their own failure records.
Use a fully materialized SDK for a full build audit.

Each board gets `build.json`, a compiler transcript, ELF, map, and HEX.
The index records the driver and example hashes, SDK versions, pin map,
compiler and stage results. The simulation job checks the ELF hash before
booting the Thermo 28 build. The standalone LAN8651 probe remains in the
peripheral regression job.

### Run the 64-driver build pilot

The [pinned sample](../examples/necto-click/pilot64.json) retains all six
cohort boards and covers 24 bus combinations, including GPIO-only drivers,
drivers with extra headers, and a multi-source library. The pilot uses the
same original C sources and compiler settings as the cohort. It exercises
build coverage with separate reports for each shard.

```bash
for shard in 0 1 2 3; do
  tools/build-click-sdk.py --corpus "$FULL_CLICK_SDK" --pilot \
    --shards 4 --shard "$shard" --out build/click-pilot64
done
```

The first pass linked 46 of 64 examples. Shared fixes added SDK delay names,
the GCC generic-pointer and byte extraction helpers, the SDK conversions
library, the STM32 OneWire build integration, and math library linkage.
All 64 then compiled and linked with Linux Arm GNU. Electronics and protocol behavior for the additional boards can be checked
in Renode or on the bench as profiles become available.

### Join the build and simulation evidence

Generate `corpus.json` with `clickforge renode-corpus`. Run
`boardforge renode-suite` against the appropriate cohort ELF and save its
`results.json`. For Thermo 28 the base board platform is
`sim/clicks/mikrobus1-i2c.repl`.

```bash
tools/report-click-sdk.py --corpus-report generated/corpus.json \
  --build-index build/click-cohort/gcc/build-index.json \
  --simulation reports/as6221/results.json --out reports/coverage.json
```

Use repeatable `--build-index` and `--simulation` options for multiple
shards and compiler lanes. The join checks SDK revision, driver content
hash, and the ELF hash. A future physical comparison can be recorded when
BoardForge receives a bench report for the same ELF. Standalone probe
results stay separate from the SDK inventory. [BoardForge bundle workflow](https://github.com/ajsb85/boardforge#renode-parity-bundles)

## CI and corpus inventory

```bash
tools/prepare-necto-clicks.sh
source tools/bench-env.sh
export NECTO_SDK_ROOT="$PWD/.cache/vendor/mikrosdk-v2"
tools/check-necto-clicks.py inventory
tools/check-necto-clicks.py verify
```

The preparation step fetches pinned shallow, sparse MikroE source trees. For the NECTO compiler on the WSL bench, use the installed SDK selected by `tools/bench-env.sh` and `tools/prepare-necto-clicks.sh --drivers-only`. The GitHub Actions workflow inventories the full pinned corpus, builds the six-driver cohort, and runs the registered simulation cases. It uploads compiler logs, ELF and HEX files, build metadata, generated scripts, UART output, and case results. The pinned corpus contains 2,018 upstream example directories. Thermo 28, Ambient, and the standalone LAN8651 probe have registered simulation cases. [Workflow](../.github/workflows/clicks.yml)

The Windows resource inventory points to the sibling `clickforge` and `boardforge` checkouts under `C:\Users\gbast\winui\firechip-forge`. Clickforge's driver IDs and model metadata can seed the inventory. Each Renode case still needs a verified socket map, a firmware build, an external model, and expected behavior. See the [Renode handoff](renode.md) for the local tools and source references.
