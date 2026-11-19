SHELL := /bin/bash
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

STM32CUBE_F7 ?= $(CURDIR)/.cache/vendor/STM32CubeF7
STM32_GCC ?= arm-none-eabi-gcc
OBJCOPY ?= arm-none-eabi-objcopy
SWIFTC ?= swiftc
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

.PHONY: all stm32cube arduino rust swift cli deps-stm32cube check-sdk
all: stm32cube arduino rust swift cli
stm32cube: build/stm32cube/hello.bin build/stm32cube/hello.hex
arduino: $(ARDUINO_TARGET).bin $(ARDUINO_TARGET).hex
rust: build/rust/hello.bin build/rust/hello.hex
swift: build/swift/hello.bin build/swift/hello.hex
cli: | .cache/tmp
	cargo build --locked --manifest-path tools/uni-cli/Cargo.toml --target-dir build/cli

.cache/tmp build/stm32cube build/arduino build/rust build/swift:
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

%.bin: %.elf
	$(OBJCOPY) -O binary "$<" "$@"

%.hex: %.elf
	$(OBJCOPY) -O ihex "$<" "$@"
