module embedded::backends::avr::atmega328p::startup @private @feat(MCU_ATMEGA328P);

import embedded::wdt;

extern fn void start();
extern fn void embedded_avr_time_init();

extern char _sbss;
extern char _ebss;

// Called for an interrupt that is enabled but has no handler. Weak, so the
// firmware can replace it (for example to blink an error code).
fn void __bad_interrupt() @weak @export("__bad_interrupt") @noreturn {
    abort();
}

// Every vector jumps to a "__vector_N" symbol. `rjmp` (+ `nop` to fill the
// 2-word slot) is used because c3c 0.8.6 does not pass the CPU to LLVM's
// inline assembler, which then silently drops `jmp`. `rjmp` reaches only
// ±4 KB, so the linker script places every vector target right after this
// table. Vectors 1 and 2 (INT0/INT1)
// are defined weakly by embedded::exti and vector 16 (TIMER0_OVF) by
// embedded::time. All others default to __bad_interrupt below and can be
// taken over by defining the symbol, see `irq::@isr`.
fn void __vectors() @naked @export("__vectors") @section(".vectors") {
    asm("rjmp __init");
    asm("nop");
    asm("rjmp __vector_1");
    asm("nop");
    asm("rjmp __vector_2");
    asm("nop");
    asm("rjmp __vector_3");
    asm("nop");
    asm("rjmp __vector_4");
    asm("nop");
    asm("rjmp __vector_5");
    asm("nop");
    asm("rjmp __vector_6");
    asm("nop");
    asm("rjmp __vector_7");
    asm("nop");
    asm("rjmp __vector_8");
    asm("nop");
    asm("rjmp __vector_9");
    asm("nop");
    asm("rjmp __vector_10");
    asm("nop");
    asm("rjmp __vector_11");
    asm("nop");
    asm("rjmp __vector_12");
    asm("nop");
    asm("rjmp __vector_13");
    asm("nop");
    asm("rjmp __vector_14");
    asm("nop");
    asm("rjmp __vector_15");
    asm("nop");
    asm("rjmp __vector_16");
    asm("nop");
    asm("rjmp __vector_17");
    asm("nop");
    asm("rjmp __vector_18");
    asm("nop");
    asm("rjmp __vector_19");
    asm("nop");
    asm("rjmp __vector_20");
    asm("nop");
    asm("rjmp __vector_21");
    asm("nop");
    asm("rjmp __vector_22");
    asm("nop");
    asm("rjmp __vector_23");
    asm("nop");
    asm("rjmp __vector_24");
    asm("nop");
    asm("rjmp __vector_25");
    asm("nop");
}

fn void __vector_3() @weak @naked @export("__vector_3") { asm("rjmp __bad_interrupt"); }
fn void __vector_4() @weak @naked @export("__vector_4") { asm("rjmp __bad_interrupt"); }
fn void __vector_5() @weak @naked @export("__vector_5") { asm("rjmp __bad_interrupt"); }
fn void __vector_6() @weak @naked @export("__vector_6") { asm("rjmp __bad_interrupt"); }
fn void __vector_7() @weak @naked @export("__vector_7") { asm("rjmp __bad_interrupt"); }
fn void __vector_8() @weak @naked @export("__vector_8") { asm("rjmp __bad_interrupt"); }
fn void __vector_9() @weak @naked @export("__vector_9") { asm("rjmp __bad_interrupt"); }
fn void __vector_10() @weak @naked @export("__vector_10") { asm("rjmp __bad_interrupt"); }
fn void __vector_11() @weak @naked @export("__vector_11") { asm("rjmp __bad_interrupt"); }
fn void __vector_12() @weak @naked @export("__vector_12") { asm("rjmp __bad_interrupt"); }
fn void __vector_13() @weak @naked @export("__vector_13") { asm("rjmp __bad_interrupt"); }
fn void __vector_14() @weak @naked @export("__vector_14") { asm("rjmp __bad_interrupt"); }
fn void __vector_15() @weak @naked @export("__vector_15") { asm("rjmp __bad_interrupt"); }
fn void __vector_17() @weak @naked @export("__vector_17") { asm("rjmp __bad_interrupt"); }
fn void __vector_18() @weak @naked @export("__vector_18") { asm("rjmp __bad_interrupt"); }
fn void __vector_19() @weak @naked @export("__vector_19") { asm("rjmp __bad_interrupt"); }
fn void __vector_20() @weak @naked @export("__vector_20") { asm("rjmp __bad_interrupt"); }
fn void __vector_21() @weak @naked @export("__vector_21") { asm("rjmp __bad_interrupt"); }
fn void __vector_22() @weak @naked @export("__vector_22") { asm("rjmp __bad_interrupt"); }
fn void __vector_23() @weak @naked @export("__vector_23") { asm("rjmp __bad_interrupt"); }
fn void __vector_24() @weak @naked @export("__vector_24") { asm("rjmp __bad_interrupt"); }
fn void __vector_25() @weak @naked @export("__vector_25") { asm("rjmp __bad_interrupt"); }

fn void abort() @export("abort") @noreturn {
    asm("rjmp .-2");
}

// Reset entry. Pure asm, because nothing compiler-generated may run before
// the stack pointer is set: it sets SP to RAMEND, clears SREG and the zero
// register r1, copies .data (and .rodata) from flash with `lpm`, which C3
// cannot express, then continues in `boot()`.
fn void __init() @naked @noreturn @export("__init") @section(".init") {
    asm("eor r1, r1");
    asm("out 0x3f, r1");                 // SREG
    asm("ldi r28, lo8(__stack_top)");
    asm("ldi r29, hi8(__stack_top)");
    asm("out 0x3e, r29");                // SPH
    asm("out 0x3d, r28");                // SPL

    asm("ldi r26, lo8(_sdata)");
    asm("ldi r27, hi8(_sdata)");
    asm("ldi r30, lo8(_sidata)");
    asm("ldi r31, hi8(_sidata)");
    asm("ldi r25, hi8(_edata)");
    asm("rjmp 2f");
    asm("1:");
    asm("lpm");
    asm("adiw r30, 1");
    asm("st X+, r0");
    asm("2:");
    asm("cpi r26, lo8(_edata)");
    asm("cpc r27, r25");
    asm("brne 1b");

    asm("rjmp embedded_avr_start");
}

// Called once after the library is initialised and interrupts are on, just
// before `start()`. Weak: define `fn void ...() @export("embedded_on_boot")`
// for board bring-up such as enabling a power rail or setting up a console.
fn void on_boot() @weak @export("embedded_on_boot") {
}

// Ordinary C3 from here on. Kept in .init so the `rjmp` above reaches it.
fn void boot() @noreturn @export("embedded_avr_start") @section(".init.boot") {
    for (char* p = &_sbss; p < &_ebss; p++) @volatile_store(*p, 0);

    wdt::boot();
    embedded_avr_time_init();
    on_boot();
    start();
    abort();
}
