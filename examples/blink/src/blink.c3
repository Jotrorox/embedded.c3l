module blink;

import embedded::gpio;
import embedded::compat::arduino;
import embedded::time;
import embedded::board;

fn void main() @export("start") {
    arduino::pin_mode(board::Pin.BUILTIN_LED, arduino::OUTPUT);

    while (true) {
        arduino::digital_write(board::Pin.BUILTIN_LED, arduino::HIGH);
        time::sleep(time::ms(500));
        arduino::digital_write(board::Pin.BUILTIN_LED, arduino::LOW);
        time::sleep(time::ms(500));
    }
}
