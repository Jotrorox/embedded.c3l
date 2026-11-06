MEMORY {
    iram  (rwx) : ORIGIN = 0x40380000, LENGTH = 368K
    dram  (rw)  : ORIGIN = 0x3FC80000, LENGTH = 384K
}

ENTRY(__init)

SECTIONS {
    .text : {
        KEEP(*(.text.init))
        /* mtvec in vectored mode needs a 256-byte aligned table. */
        . = ALIGN(256);
        KEEP(*(.text.vectors))
        *(.text*)
        . = ALIGN(4);
        _iram_end = .;
    } > iram

    /* IRAM 0x4038_0000 and DRAM 0x3FC8_0000 are the same physical SRAM seen
       through two buses, so data must start where the code ends or the two
       would overwrite each other (ESP-IDF's .dram0.dummy does the same). */
    .dram_dummy (NOLOAD) : {
        . = ORIGIN(dram) + (_iram_end - ORIGIN(iram));
    } > dram

    /* Constants live in DRAM, next to .data, so byte and halfword loads work
       and they do not take instruction RAM. The ROM loader copies both. */
    .data : {
        __data_start = .;
        *(.rodata*)
        *(.srodata*)
        *(.data*)
        *(.sdata*)
        __data_end = .;
    } > dram

    /* Cleared by the start-up code. */
    .bss (NOLOAD) : {
        __bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > dram

    /DISCARD/ : {
        *(.eh_frame*)
        *(.eh_frame_hdr*)
        *(.comment)
        *(.note*)
    }

    __stack_top = ORIGIN(dram) + LENGTH(dram);
}
