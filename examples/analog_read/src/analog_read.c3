module analog_read;

import embedded::adc;
import embedded::gpio;
import embedded::time;
import embedded::uart;
import embedded::board;

// Prints the voltage on an analog pin twice a second, for example the wiper
// of a potentiometer between GND and 3.3 V / 5 V.
const gpio::Pin ANALOG_PIN @feat(BOARD_ARDUINO_UNO) = board::Pin.A0;
const gpio::Pin ANALOG_PIN @feat(BOARD_ESP32C3_SUPERMINI) = board::Pin.GPIO2;

fn void firmware_start() @export("start") {
    uart::Uart console = uart::open(board::CONSOLE)!!;
    adc::Input input = adc::open(ANALOG_PIN)!!;

    while (true) {
        ushort raw = input.read();
        console.write("raw ");
        console.write_uint(raw);
        console.write("  ~");
        console.write_uint(input.read_millivolts());
        console.write_line(" mV");
        time::sleep(time::ms(500));
    }
}
