module watchdog;

import embedded::wdt;
import embedded::time;
import embedded::compat::arduino;
import embedded::board;

// Arms a 1 s watchdog, feeds it while blinking slowly for a few seconds, then
// "hangs" without feeding. The watchdog resets the chip, and on the next boot
// the LED flashes quickly a few times to show that the reset came from the
// watchdog before the cycle starts again.
const int FED_BLINKS = 5;

fn void flash(int count, uint period_ms) {
    for (int i = 0; i < count; i++) {
        arduino::digital_write(board::Pin.BUILTIN_LED, HIGH);
        arduino::delay(period_ms / 2);
        arduino::digital_write(board::Pin.BUILTIN_LED, LOW);
        arduino::delay(period_ms / 2);
    }
}

fn void firmware_start() @export("start") {
    arduino::pin_mode(board::Pin.BUILTIN_LED, OUTPUT);

    if (wdt::caused_reset()) flash(10, 100);

    // Rounded up to what the hardware supports: 1.024 s on AVR, exactly 1 s on ESP32-C3.
    if (catch wdt::enable(time::ms(1000))) {
        while (true) flash(1, 2000);
    }

    for (int i = 0; i < FED_BLINKS; i++) {
        flash(1, 800);
        wdt::feed();
    }

    arduino::digital_write(board::Pin.BUILTIN_LED, HIGH);
    while (true) {}
}
