module uart_echo;

import embedded::uart;
import embedded::time;
import embedded::board;

// Echoes everything typed on the board console back, and prints the uptime
// every few seconds. Open a serial monitor at 115200 baud on the board's USB
// port (on the ESP32-C3 SuperMini the baud rate does not matter).
fn void firmware_start() @export("start") {
    uart::Uart console = uart::open(board::CONSOLE)!!;
    console.write_line("embedded.c3l uart_echo: type something");

    time::Instant next_report = time::deadline_after(time::seconds(5));
    while (true) {
        if (try byte = console.try_read()) {
            console.write_byte(byte);
            if (byte == '\r') console.write_byte('\n');
        }
        if (time::has_elapsed(next_report)) {
            console.write("uptime ms: ");
            console.write_uint(time::as_ms(time::since_boot()));
            console.write_line("");
            next_report = time::deadline_after(time::seconds(5));
        }
    }
}
