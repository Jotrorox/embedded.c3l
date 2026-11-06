/* ATmega328P (Arduino Uno) memory layout.

   Symbols the start-up code and future allocators use:
     _sdata/_edata, _sidata    .data in SRAM and its load address in flash
     _sbss/_ebss               .bss, cleared at boot
     __heap_start/__heap_end   free SRAM between .noinit and the stack
     __stack_top               initial SP (RAMEND); the stack grows down

   Override the stack reserve with `--defsym=__stack_size=<bytes>` in the
   target's link-args. */

ENTRY(__init)

MEMORY {
    FLASH  (rx)   : ORIGIN = 0x000000, LENGTH = 32K
    SRAM   (rw!x) : ORIGIN = 0x800100, LENGTH = 2K
    /* EEPROM is not memory-mapped; 0x810000 is the avr-gcc convention for
       EEPROM contents in an ELF file. */
    EEPROM (rw!x) : ORIGIN = 0x810000, LENGTH = 1K
}

/* SRAM that must stay free for the stack. A link that leaves less fails. */
__stack_size = DEFINED(__stack_size) ? __stack_size : 128;

SECTIONS {
    .text 0x0 : {
        KEEP(*(.vectors))
        KEEP(*(.init*))
        /* Everything the vector table and __init reach with `rjmp` (±4 KB)
           comes first: the vectors, the C start-up function, the shared ISR
           trampoline and the default handler. __unnamed_* is the body LLVM
           merges the identical weak default vectors into. */
        *(.text.__vector_*)
        *(.text.__irq_call_z)
        *(.text.__unnamed_*)
        *(.text.__bad_interrupt)
        *(.text.abort)
        *(.text*)
        _etext = .;
    } > FLASH

    /* Classic AVR cannot read flash with ordinary loads, so constants
       (.rodata) are copied to SRAM with the initialised data, so every
       constant table costs RAM as well as flash. */
    .data : {
        _sdata = .;
        *(.data*)
        *(.rodata*)
        _edata = .;
    } > SRAM AT> FLASH
    _sidata = LOADADDR(.data);
    PROVIDE(_sdata = ADDR(.data));
    PROVIDE(_edata = ADDR(.data) + SIZEOF(.data));

    .bss (NOLOAD) : {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > SRAM
    PROVIDE(_sbss = ADDR(.bss));
    PROVIDE(_ebss = ADDR(.bss) + SIZEOF(.bss));

    /* Neither loaded nor cleared, so it survives a watchdog or external
       reset. Place a variable here with @section(".noinit"). */
    .noinit (NOLOAD) : {
        *(.noinit*)
    } > SRAM

    __heap_start = .;
    __stack_top = ORIGIN(SRAM) + LENGTH(SRAM) - 1;
    __heap_end = __stack_top + 1 - __stack_size;

    /* Initial EEPROM contents, @section(".eeprom"). Not part of the flash
       image: convert with `avr-objcopy -O ihex -R .eeprom` for flash and
       `-j .eeprom --change-section-lma .eeprom=0` for the EEPROM. */
    .eeprom : {
        KEEP(*(.eeprom*))
    } > EEPROM
}

ASSERT(__heap_start <= __heap_end,
       "SRAM overflow: .data + .bss + .noinit leave less than __stack_size bytes for the stack")
