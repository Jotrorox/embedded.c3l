ENTRY(__init)

MEMORY {
    FLASH (rx)   : ORIGIN = 0x000000, LENGTH = 32K
    SRAM  (rw!x) : ORIGIN = 0x800100, LENGTH = 2K
}

SECTIONS {
    .text 0x0 : {
        KEEP(*(.vectors))
        KEEP(*(.init*))
        *(.text*)
        _etext = .;
    } > FLASH

    .data : AT(_etext) {
        _sdata = .;
        *(.data*)
        *(.rodata*)
        _edata = .;
    } > SRAM
    PROVIDE(_sdata = ADDR(.data));
    PROVIDE(_edata = ADDR(.data) + SIZEOF(.data));

    .bss : {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > SRAM
    PROVIDE(_sbss = ADDR(.bss));
    PROVIDE(_ebss = ADDR(.bss) + SIZEOF(.bss));
}
