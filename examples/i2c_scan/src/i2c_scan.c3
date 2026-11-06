module i2c_scan;

import embedded::i2c;
import embedded::time;
import embedded::uart;
import embedded::board;

// Probes every 7-bit address on the board's default I2C pins every five
// seconds and prints the ones that answer.
fn void firmware_start() @export("start") {
    uart::Uart console = uart::open(board::CONSOLE)!!;
    i2c::Bus bus = i2c::open()!!;

    while (true) {
        console.write_line("scanning I2C bus...");
        uint found = 0;
        for (char address = 0x08; address < 0x78; address++) {
            if (!bus.probe(address)) continue;
            console.write("  device at 0x");
            console.write_hex(address, 2);
            console.write_line("");
            found++;
        }
        console.write_uint(found);
        console.write_line(" device(s) found");
        time::sleep(time::seconds(5));
    }
}
