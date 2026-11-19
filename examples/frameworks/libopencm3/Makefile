OPENCM3 ?=
OUT ?= ../../../build/libopencm3
CC := arm-none-eabi-gcc
CPU := -mcpu=cortex-m7 -mthumb -mfpu=fpv5-sp-d16 -mfloat-abi=hard

.PHONY: all
all: $(OUT)/hello.elf

$(OUT)/hello.elf: main.c flash.ld
	test -f "$(OPENCM3)/lib/libopencm3_stm32f7.a"
	mkdir -p "$(OUT)"
	$(CC) $(CPU) -Og -g3 -DSTM32F7 -I"$(OPENCM3)/include" -ffunction-sections -fdata-sections \
		-nostartfiles -L"$(OPENCM3)/lib" -Tflash.ld -Wl,--gc-sections -o "$@" main.c -lopencm3_stm32f7
