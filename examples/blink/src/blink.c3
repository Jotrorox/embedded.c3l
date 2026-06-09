module blink;

import embedded::compat::arduino;
import embedded::board;

fn void main() @export("start") {
    arduino::pin_mode(board::Pin.BUILTIN_LED, OUTPUT);

    while (true) {
        arduino::digital_write(board::Pin.BUILTIN_LED, HIGH);
        arduino::delay(500);
        arduino::digital_write(board::Pin.BUILTIN_LED, LOW);
        arduino::delay(500);
    }
}
