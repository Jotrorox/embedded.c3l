module embedded::backends::esp32::esp32c3::startup @private;

import embedded::wdt;
import embedded::irq;

extern fn void start();

extern char __bss_start;
extern char __bss_end;

// Entry point. Only sets up the stack and the trap vector, then continues in
// a normal function, so no compiler-generated code runs without a stack.
fn void __init() @naked @noreturn @export("__init") @section(".text.init") {
    asm("la sp, __stack_top");
    asm("la t0, embedded_esp32_vectors");
    asm("ori t0, t0, 1"); // vectored mode
    asm("csrw mtvec, t0");
    asm("j embedded_esp32_start");
}

// Called once after the library is initialised and interrupts are on, just
// before `start()`. Weak: define `fn void ...() @export("embedded_on_boot")`
// for board bring-up such as enabling a power rail or setting up a console.
fn void on_boot() @weak @export("embedded_on_boot") {
}

fn void boot() @noreturn @export("embedded_esp32_start") {
    // The ROM loader only copies loadable sections, so .bss holds whatever
    // the ROM left in RAM until it is cleared here.
    for (char* p = &__bss_start; p < &__bss_end; p++) @volatile_store(*p, 0);

    irq::init();
    wdt::boot();
    irq::enable();

    on_boot();
    start();
    while (true) asm("wfi");
}
