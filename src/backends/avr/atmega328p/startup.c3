module embedded::backends::avr::atmega328p::startup @private;

extern fn void start();
extern fn void embedded_avr_time_init();

extern char _sdata;
extern char _edata;
extern char _sbss;
extern char _ebss;
extern char _etext;

fn void __bad_interrupt() @export("__bad_interrupt") @noreturn {
    abort();
}

fn void __vectors() @naked @export("__vectors") @section(".vectors") {
    asm("rjmp __init");
    asm("nop");
    asm("rjmp __vector_1");
    asm("nop");
    asm("rjmp __vector_2");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __vector_16");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
    asm("rjmp __bad_interrupt");
    asm("nop");
}

fn void __vector_1() @export("__vector_1") {
    __bad_interrupt();
}

fn void __vector_2() @export("__vector_2") {
    __bad_interrupt();
}

fn void abort() @export("abort") @noreturn {
    asm("rjmp .-2");
}

fn void __init() @naked @noreturn @export("__init") @section(".init") {
    asm("ldi r28, 0xFF");
    asm("out 0x3d, r28");
    asm("ldi r29, 0x08");
    asm("out 0x3e, r29");
    asm("eor r1, r1");

    asm("ldi r26, lo8(_sdata)");
    asm("ldi r27, hi8(_sdata)");
    asm("ldi r30, lo8(_etext)");
    asm("ldi r31, hi8(_etext)");
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

    char* bss = &_sbss;
    char* bend = &_ebss;
    while (bss < bend) {
        *bss = 0;
        bss++;
    }

    embedded_avr_time_init();
    start();
    abort();
}
