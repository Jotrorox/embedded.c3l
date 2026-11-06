module spi_loopback;

import embedded::spi;
import embedded::time;
import embedded::uart;
import embedded::board;

// Sends a test pattern and checks that it comes back. Connect MOSI to MISO
// with a wire (Uno: D11-D12; SuperMini: GPIO6-GPIO5).
fn void firmware_start() @export("start") {
    uart::Uart console = uart::open(board::CONSOLE)!!;
    spi::Bus bus = spi::open({ .frequency_hz = 1_000_000 })!!;

    char[100] sent;
    char[100] received;
    for (usz i = 0; i < sent.len; i++) sent[i] = (char)(i * 7 + 3);

    while (true) {
        bus.transfer(&sent, &received)!!;
        usz errors = 0;
        for (usz i = 0; i < sent.len; i++) {
            if (sent[i] != received[i]) errors++;
        }
        console.write("SPI loopback at ");
        console.write_uint(bus.frequency());
        console.write(" Hz: ");
        console.write_uint(errors);
        console.write_line(errors == 0 ? " errors, OK" : " errors (is MOSI wired to MISO?)");
        time::sleep(time::seconds(2));
    }
}
