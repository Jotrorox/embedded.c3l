module button_irq;

import embedded::exti;
import embedded::gpio;
import embedded::irq;
import embedded::time;
import embedded::board;

// Toggles the built-in LED from a pin interrupt each time an active-low button
// is pressed, while the main loop sleeps. Uno: button between D2 and GND.
// SuperMini: the BOOT button on GPIO9.
const gpio::Pin BUTTON_PIN @feat(BOARD_ARDUINO_UNO) = board::Pin.D2;
const gpio::Pin BUTTON_PIN @feat(BOARD_ESP32C3_SUPERMINI) = board::Pin.GPIO9;

const ulong DEBOUNCE_US = 50_000;

gpio::Output led;
time::Instant last_press;

// Runs in interrupt context: keep it short. `time::now()` is safe to call
// here; it only reads the clock.
fn void on_press() {
    time::Instant now = time::now();
    if (time::as_us(time::elapsed_between(last_press, now)) < DEBOUNCE_US) return;
    last_press = now;
    led.toggle();
}

fn void firmware_start() @export("start") {
    led = gpio::output(board::Pin.BUILTIN_LED)!!;
    (void)gpio::input(BUTTON_PIN, UP)!!;
    exti::attach(BUTTON_PIN, FALLING, &on_press)!!;

    while (true) time::sleep(time::seconds(1));
}
