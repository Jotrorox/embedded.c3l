module embedded::uart;

import embedded::time;

// Host stand-in for a UART backend. Written bytes go to `fake_tx`; reads come
// from `fake_rx` and advance the fake clock by `fake_read_cost_us` per poll,
// so timeouts expire without a real clock.

typedef Port = char;

struct Uart {
    Port port;
}

char[256] fake_tx;
usz fake_tx_len;
char[] fake_rx;
usz fake_rx_pos;
ulong fake_read_cost_us = 10;

fn void fake_reset() {
    fake_tx_len = 0;
    fake_rx = {};
    fake_rx_pos = 0;
}

fn char[] fake_output() => fake_tx[:fake_tx_len];

fn void Uart.write_byte(self, char byte) {
    assert(fake_tx_len < fake_tx.len, "fake UART output overflow");
    fake_tx[fake_tx_len++] = byte;
}

fn void Uart.write(self, char[] bytes) {
    foreach (b : bytes) self.write_byte(b);
}

fn bool Uart.can_read(self) => fake_rx_pos < fake_rx.len;

fn char? Uart.try_read(self) {
    time::fake_advance(fake_read_cost_us);
    if (fake_rx_pos >= fake_rx.len) return NO_DATA~;
    return fake_rx[fake_rx_pos++];
}
