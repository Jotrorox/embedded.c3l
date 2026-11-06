ENTRY(__init)

MEMORY {
    FLASH (rx)   : ORIGIN = 0x000000, LENGTH = 32K
    SRAM  (rw!x) : ORIGIN = 0x800100, LENGTH = 2K
}

SECTIONS {
    .text 0x0 : {
        KEEP(*(.vectors))
        KEEP(*(.init*))
        /* Everything the vector table reaches with `rjmp` (±4 KB) comes
           first: the vectors, the shared ISR trampoline and the default
           handler. __unnamed_* is the body LLVM merges the identical weak
           default vectors into. */
        *(.text.__vector_*)
        *(.text.__irq_call_z)
        *(.text.__unnamed_*)
        *(.text.__bad_interrupt)
        *(.text.abort)
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
