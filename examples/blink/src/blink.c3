module blink;

import embedded::gpio;
import embedded::time;
import embedded::board;

fn void main() @export("start") {
    gpio::pin_mode(board::Pin.BUILTIN_LED, OUTPUT);

    while (true) {
        gpio::digital_write(board::Pin.BUILTIN_LED, HIGH);
        time::delay_ms(500);
        gpio::digital_write(board::Pin.BUILTIN_LED, LOW);
        time::delay_ms(500);
    }
}
