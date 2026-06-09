module uart_echo;

import embedded::uart;

fn void main() @export("start") {
    uart::begin(115200);
    uart::printn("embedded.c3l uart echo ready");
    uart::printn("send bytes and they will be echoed back");

    while (true) {
        if (uart::can_read()) {
            char c = uart::read();
            uart::write_byte(c);
        }
    }
}
