MEMORY {
    iram  (rwx) : ORIGIN = 0x40380000, LENGTH = 368K
    dram  (rw)  : ORIGIN = 0x3FC80000, LENGTH = 384K
}

ENTRY(__init)

SECTIONS {
    .text : {
        KEEP(*(.text.init))
        *(.text*)
        *(.rodata*)
    } > iram

    .data : {
        __data_start = .;
        *(.data*)
        __data_end = .;
    } > dram

    .bss (NOLOAD) : {
        __bss_start = .;
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
