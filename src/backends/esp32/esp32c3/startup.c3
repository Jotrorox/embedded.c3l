module embedded::backends::esp32::esp32c3::startup @private;

import embedded::wdt;

extern fn void start();

fn void __init() @naked @noreturn @export("__init") @section(".text.init") {
    asm("la sp, __stack_top");
    wdt::boot();

    start();
    while (true) {}
}
