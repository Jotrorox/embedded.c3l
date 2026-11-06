module digital_read;

import embedded::gpio;
import embedded::time;
import embedded::board;

const gpio::Pin BUTTON_PIN @feat(BOARD_ARDUINO_UNO) = board::Pin.A5;
const gpio::Pin BUTTON_PIN @feat(BOARD_ESP32C3_SUPERMINI) = board::Pin.GPIO9;

// Mirrors an active-low button onto the built-in LED, using the native GPIO
// API: `gpio::input()` / `gpio::output()` configure the pins once and return
// handles whose methods cannot fail and need no per-call validation.
fn void firmware_start() @export("start") {
    // Both pins are board constants known to support these modes, so a fault
    // here would be a programming error; `!!` turns it into a panic.
    gpio::Input button = gpio::input(BUTTON_PIN, UP)!!;
    gpio::Output led = gpio::output(board::Pin.BUILTIN_LED)!!;

    while (true) {
        led.write(button.is_low() ? HIGH : LOW);
        time::sleep(time::ms(25));
    }
}
