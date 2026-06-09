module digital_read;

import embedded::gpio;
import embedded::compat::arduino;
import embedded::board;

const gpio::Pin BUTTON_PIN @if($feature(BOARD_ARDUINO_UNO)) = board::Pin.A5;
const gpio::Pin BUTTON_PIN @if($feature(BOARD_ESP32C3_SUPERMINI)) = board::Pin.GPIO9;

fn void main() @export("start") {
    arduino::pin_mode(BUTTON_PIN, INPUT_PULLUP);
    arduino::pin_mode(board::Pin.BUILTIN_LED, OUTPUT);

    while (true) {
        gpio::PinState button = arduino::digital_read(BUTTON_PIN);
        arduino::digital_write(board::Pin.BUILTIN_LED, button == LOW ? HIGH : LOW);
        arduino::delay(25);
    }
}
