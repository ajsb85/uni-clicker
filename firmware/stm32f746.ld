ENTRY(Reset_Handler)

MEMORY {
    FLASH (rx) : ORIGIN = 0x08000000, LENGTH = 1M
    RAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 320K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS {
    .isr_vector : { KEEP(*(.isr_vector)) } > FLASH
    .text : { *(.text .text.*) *(.rodata .rodata.*) } > FLASH
    .ARM.extab : { *(.ARM.extab*) } > FLASH
    .ARM.exidx : {
        __exidx_start = .;
        *(.ARM.exidx*)
        __exidx_end = .;
    } > FLASH
    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data .data.*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT > FLASH
    _sidata = LOADADDR(.data);
    .bss (NOLOAD) : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss .bss.*) *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM
    /DISCARD/ : { *(.note.GNU-stack) }
}

ASSERT(_ebss <= _estack - 4096, "RAM must leave at least 4 KiB for the stack")
