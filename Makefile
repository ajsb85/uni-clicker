SHELL := /bin/bash
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

STM32CUBE_F7 ?= $(CURDIR)/.cache/vendor/STM32CubeF7
STM32_GCC ?= arm-none-eabi-gcc
OBJCOPY ?= arm-none-eabi-objcopy
SWIFTC ?= swiftc
ZIG ?= zig
MICROZIG ?= $(CURDIR)/.cache/vendor/microzig
NECTO_SDK_ROOT ?=
FREERTOS_ROOT ?=
THREADX_ROOT ?=
OPENCM3 ?=
ARDUINO_CLI ?= arduino-cli
ARDUINO_FQBN := STMicroelectronics:stm32:GenF7:pnum=GENERIC_F746ZGTX,xserial=none,usb=none
ARDUINO_TARGET := build/arduino/HelloUni.ino
RUST_TRIPLE := thumbv7em-none-eabihf

CMSIS := $(STM32CUBE_F7)/Drivers/CMSIS
DEVICE := $(CMSIS)/Device/ST/STM32F7xx
HAL := $(STM32CUBE_F7)/Drivers/STM32F7xx_HAL_Driver
STARTUP := $(DEVICE)/Source/Templates/gcc/startup_stm32f746xx.s $(DEVICE)/Source/Templates/system_stm32f7xx.c firmware/startup_support.c
HAL_SRC := $(addprefix $(HAL)/Src/stm32f7xx_hal, .c _cortex.c _gpio.c _uart.c _rcc.c _rcc_ex.c _dma.c)
CPU := -mcpu=cortex-m7 -mthumb
CFLAGS := -g3 -Os -ffunction-sections -fdata-sections -Wall -Wextra -DSTM32F746xx -I$(CMSIS)/Include -I$(DEVICE)/Include
LINK = -Tfirmware/stm32f746.ld -Wl,--gc-sections,-z,noexecstack,-Map,$(@:.elf=.map)
export TMPDIR := $(CURDIR)/.cache/tmp

.PHONY: all stm32cube arduino rust swift zig necto necto-windows mikroc mikroc-source-check freertos threadx libopencm3 cli deps-stm32cube check-sdk check-microzig
all: stm32cube arduino rust swift cli
stm32cube: build/stm32cube/hello.bin build/stm32cube/hello.hex
arduino: $(ARDUINO_TARGET).bin $(ARDUINO_TARGET).hex
rust: build/rust/hello.bin build/rust/hello.hex
swift: build/swift/hello.bin build/swift/hello.hex
zig: build/zig/hello.bin build/zig/hello.hex
necto: build/necto/hello.bin build/necto/hello.hex
necto-windows: build/necto-windows/hello.bin build/necto-windows/hello.hex
freertos: build/freertos/hello.bin build/freertos/hello.hex
threadx: build/threadx/hello.bin build/threadx/hello.hex
libopencm3: build/libopencm3/hello.bin build/libopencm3/hello.hex
mikroc-source-check: build/mikroc-source-check/hello.bin build/mikroc-source-check/hello.hex
mikroc:
	tools/build-mikroc.sh
cli: | .cache/tmp
	cargo build --locked --manifest-path tools/uni-cli/Cargo.toml --target-dir build/cli

.cache/tmp build/stm32cube build/arduino build/rust build/swift build/zig build/necto build/mikroc-source-check:
	mkdir -p "$@"

deps-stm32cube: | .cache/tmp
	tools/fetch-stm32cube.sh "$(STM32CUBE_F7)"

check-sdk:
	@test -f "$(DEVICE)/Include/stm32f746xx.h" || { echo 'Run make deps-stm32cube or set STM32CUBE_F7.' >&2; exit 1; }

build/stm32cube/hello.elf: examples/stm32cube/main.c examples/stm32cube/stm32f7xx_hal_conf.h firmware/stm32f746.ld firmware/startup_support.c Makefile | check-sdk .cache/tmp build/stm32cube
	$(STM32_GCC) $(CPU) -mfpu=fpv5-sp-d16 -mfloat-abi=hard $(CFLAGS) -I$(HAL)/Inc -Iexamples/stm32cube -nostartfiles --specs=nano.specs --specs=nosys.specs $(LINK) $< $(STARTUP) $(HAL_SRC) -o "$@"

$(ARDUINO_TARGET).elf: examples/arduino/HelloUni/HelloUni.ino Makefile | .cache/tmp build/arduino
	$(ARDUINO_CLI) compile --optimize-for-debug --fqbn "$(ARDUINO_FQBN)" --build-path "$(CURDIR)/build/arduino" --jobs 4 examples/arduino/HelloUni

build/rust/hello.elf: examples/rust/src/main.rs examples/rust/build.rs examples/rust/memory.x examples/rust/Cargo.toml examples/rust/Cargo.lock Makefile | .cache/tmp build/rust
	cargo build --locked --release --target $(RUST_TRIPLE) --manifest-path examples/rust/Cargo.toml --target-dir build/rust/cargo
	cp "build/rust/cargo/$(RUST_TRIPLE)/release/uni-rust-hello" "$@"

build/swift/hello.o: examples/swift/Hello.swift examples/swift/CBoard/board.h examples/swift/CBoard/module.modulemap Makefile | .cache/tmp build/swift
	"$(SWIFTC)" -target armv7em-none-none-eabi -enable-experimental-feature Embedded -wmo -parse-as-library -Osize -g -Xfrontend -no-allocations -Xfrontend -function-sections -Xfrontend -dwarf-version=4 -Xfrontend -no-clang-module-breadcrumbs -module-cache-path "$(CURDIR)/.cache/swift-modules" -Xcc -ffreestanding -I examples/swift/CBoard -c "$<" -o "$@"
	# swiftc can preserve the timestamp when the object is unchanged.
	touch -c "$@"

build/swift/hello.elf: examples/swift/board.c examples/swift/CBoard/board.h firmware/stm32f746.ld firmware/startup_support.c build/swift/hello.o Makefile | check-sdk .cache/tmp build/swift
	$(STM32_GCC) $(CPU) -mfloat-abi=soft $(CFLAGS) -Iexamples/swift/CBoard -fno-short-enums -nostdlib $(LINK) $< $(STARTUP) build/swift/hello.o -o "$@"

check-microzig:
	@test -f "$(MICROZIG)/build.zig" || { echo 'Set MICROZIG to a MicroZig 0.17.41 checkout.' >&2; exit 1; }
	@if [[ ! -e .cache/vendor/microzig ]]; then mkdir -p .cache/vendor; ln -s "$$(realpath "$(MICROZIG)")" .cache/vendor/microzig; fi
	@test "$$(realpath "$(MICROZIG)")" = "$$(realpath .cache/vendor/microzig)"

build/zig/hello.elf: examples/zig/build.zig examples/zig/build.zig.zon examples/zig/src/main.zig | check-microzig .cache/tmp build/zig
	tools/build-zig.sh "$(ZIG)"
	cp build/zig/microzig/firmware/hello.elf "$@"

build/necto/hello.elf: examples/necto/main.c examples/necto/CMakeLists.txt examples/necto/arm-gcc.cmake firmware/stm32f746.ld firmware/startup_support.c | check-sdk .cache/tmp build/necto
	cmake -S examples/necto -B build/necto -DCMAKE_TOOLCHAIN_FILE="$(CURDIR)/examples/necto/arm-gcc.cmake" -DSTM32CUBE_F7="$(STM32CUBE_F7)" -DNECTO_SDK_ROOT="$(NECTO_SDK_ROOT)"
	cmake --build build/necto --parallel 4

build/mikroc-source-check/hello.elf: examples/mikroc/cmsis-source-check.c examples/mikroc/hello.c firmware/stm32f746.ld firmware/startup_support.c | check-sdk .cache/tmp build/mikroc-source-check
	$(STM32_GCC) $(CPU) -mfloat-abi=soft $(CFLAGS) -nostdlib $(LINK) $< $(STARTUP) -o "$@"

build/necto-windows/hello.elf: build/necto/hello.elf tools/build-necto-windows.sh
	tools/build-necto-windows.sh "$(STM32CUBE_F7)"

build/freertos/hello.elf: examples/frameworks/freertos/main.c examples/frameworks/freertos/FreeRTOSConfig.h
build/freertos/hello.elf: KERNEL_DIR = $(FREERTOS_ROOT)
build/threadx/hello.elf: examples/frameworks/threadx/main.c examples/frameworks/threadx/platform.c
build/threadx/hello.elf: KERNEL_DIR = $(THREADX_ROOT)
build/freertos/hello.elf build/threadx/hello.elf: examples/frameworks/CMakeLists.txt examples/frameworks/common/board.c examples/frameworks/common/board.h examples/necto/arm-gcc.cmake firmware/stm32f746.ld firmware/startup_support.c | check-sdk .cache/tmp
	cmake -S examples/frameworks -B "$(@D)" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$(CURDIR)/examples/necto/arm-gcc.cmake" -DSTM32CUBE_F7="$(STM32CUBE_F7)" -DFRAMEWORK="$(notdir $(@D))" -DKERNEL_DIR="$(KERNEL_DIR)"
	cmake --build "$(@D)" --parallel 4

build/libopencm3/hello.elf: examples/frameworks/libopencm3/main.c examples/frameworks/libopencm3/Makefile examples/frameworks/libopencm3/flash.ld | .cache/tmp
	$(MAKE) -C examples/frameworks/libopencm3 OPENCM3="$(OPENCM3)" OUT="$(CURDIR)/build/libopencm3"

%.bin: %.elf
	$(OBJCOPY) -O binary "$<" "$@"

%.hex: %.elf
	$(OBJCOPY) -O ihex "$<" "$@"
