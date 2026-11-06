/* ESP32-C3 memory layout. The ROM loader copies .text into IRAM and .data
   into DRAM; there is no flash (XIP) mapping yet.

   Symbols the start-up code and future allocators use:
     __data_start/__data_end   .rodata + .data, loaded by the ROM
     __bss_start/__bss_end     .bss, cleared at boot
     __heap_start/__heap_end   free DRAM between .noinit and the stack
     __stack_top               initial sp; the stack grows down

   Override the stack reserve with `--defsym=__stack_size=<bytes>` in the
   target's link-args. */

MEMORY {
    iram  (rwx) : ORIGIN = 0x40380000, LENGTH = 368K
    dram  (rw)  : ORIGIN = 0x3FC80000, LENGTH = 384K
}

ENTRY(__init)

/* DRAM that must stay free for the stack. A link that leaves less fails. */
__stack_size = DEFINED(__stack_size) ? __stack_size : 8K;

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

    /* Neither loaded nor cleared, so it survives a software or watchdog
       reset. Place a variable here with @section(".noinit"). */
    .noinit (NOLOAD) : {
        *(.noinit*)
    } > dram

    __heap_start = ALIGN(16);

    /DISCARD/ : {
        *(.eh_frame*)
        *(.eh_frame_hdr*)
        *(.comment)
        *(.note*)
    }

    __stack_top = ORIGIN(dram) + LENGTH(dram);
    __heap_end = __stack_top - __stack_size;
}

ASSERT(__heap_start <= __heap_end,
       "DRAM overflow: code + .data + .bss + .noinit leave less than __stack_size bytes for the stack")
