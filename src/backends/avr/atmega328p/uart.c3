module embedded::uart;

import embedded::gpio;
import embedded::irq;
import embedded::backends::avr::atmega328p::soc;

// USART0, the ATmega328P's only UART: TX on PD1 (D1), RX on PD0 (D0).
// Enabling the transmitter and receiver takes the pins over from GPIO.
constdef Port : inline char {
    UART0 = 0,
}

const uint UCSR0A = 0xC0;
const uint UCSR0B = 0xC1;
const uint UCSR0C = 0xC2;
const uint UBRR0L = 0xC4;
const uint UBRR0H = 0xC5;
const uint UDR0   = 0xC6;

// UCSR0A
const char RXC0  = 1 << 7;
const char TXC0  = 1 << 6;
const char UDRE0 = 1 << 5;
const char FE0   = 1 << 4;
const char DOR0  = 1 << 3;
const char UPE0  = 1 << 2;
const char U2X0  = 1 << 1;
// UCSR0B
const char RXEN0 = 1 << 4;
const char TXEN0 = 1 << 3;
// UCSR0C
const char UPM01 = 1 << 5;
const char UPM00 = 1 << 4;
const char USBS0 = 1 << 3;
const char UCSZ_SHIFT = 1;

const gpio::Pin TX_PIN = (gpio::Pin)1;
const gpio::Pin RX_PIN = (gpio::Pin)0;

// Rate error limit for UNSUPPORTED_BAUD, in parts per thousand. 115200 baud
// from 16 MHz is 2.1 % fast, which 8N1 receivers tolerate.
const uint MAX_BAUD_ERROR_PERMILLE = 25;

struct Uart {
    Port port;
}

// TXC0 is only set by hardware after a byte has been shifted out, so
// `flush()` must know whether anything was sent since the last flush.
bool tx_pending @local = false;

fn bool is_valid(Port port) => port == Port.UART0;

fn Uart? open(Port port, Config config = {}) {
    return open_pins(port, TX_PIN, RX_PIN, config);
}

// Rate produced by a UBRR value: f / (16 * (UBRR + 1)), or 8 with U2X.
fn uint rate_for(uint ubrr, bool double_speed) @local {
    return soc::CPU_HZ / ((double_speed ? 8u : 16u) * (ubrr + 1));
}

fn uint error_permille(uint actual, uint wanted) @local {
    uint diff = actual > wanted ? actual - wanted : wanted - actual;
    return (uint)((ulong)diff * 1000 / wanted);
}

fn Uart? open_pins(Port port, gpio::Pin tx, gpio::Pin rx, Config config = {}) {
    if (!is_valid(port)) return INVALID_PORT~;
    if (tx != TX_PIN || rx != RX_PIN) return INVALID_PINS~;

    uint baud = config.baud == 0 ? DEFAULT_BAUD : config.baud;
    if (baud > soc::CPU_HZ / 8) return UNSUPPORTED_BAUD~;

    // Try double speed (finer steps at high rates) and normal speed, and keep
    // whichever is closer.
    uint ubrr_fast = (soc::CPU_HZ / 4 / baud - 1) / 2;
    uint ubrr_slow = (soc::CPU_HZ / 8 / baud - 1) / 2;
    // Low rates only fit at normal speed (UBRR is 12 bits).
    if (ubrr_fast > 4095 && ubrr_slow > 4095) return UNSUPPORTED_BAUD~;
    uint err_fast = ubrr_fast <= 4095 ? error_permille(rate_for(ubrr_fast, true), baud) : 0xFFFF_FFFF;
    uint err_slow = ubrr_slow <= 4095 ? error_permille(rate_for(ubrr_slow, false), baud) : 0xFFFF_FFFF;
    bool double_speed = err_fast <= err_slow;
    uint ubrr = double_speed ? ubrr_fast : ubrr_slow;
    if ((double_speed ? err_fast : err_slow) > MAX_BAUD_ERROR_PERMILLE) return UNSUPPORTED_BAUD~;

    // UCSZ0[1:0] is 3 for 8 data bits down to 0 for 5.
    if ((char)config.data_bits > 3) return UNSUPPORTED_FORMAT~;
    char frame = (char)((3 - (char)config.data_bits) << UCSZ_SHIFT);
    switch (config.parity) {
        case Parity.NONE: break;
        case Parity.EVEN: frame |= UPM01;
        case Parity.ODD:  frame |= UPM01 | UPM00;
        default: return UNSUPPORTED_FORMAT~;
    }
    if (config.stop_bits == StopBits.TWO) frame |= USBS0;

    soc::write8(UCSR0B, 0);
    soc::write8(UCSR0A, double_speed ? U2X0 : 0);
    soc::write8(UBRR0H, (char)(ubrr >> 8));
    soc::write8(UBRR0L, (char)ubrr);
    soc::write8(UCSR0C, frame);
    soc::write8(UCSR0B, RXEN0 | TXEN0);
    tx_pending = false;
    return { port };
}

fn void Uart.close(self) {
    self.flush();
    soc::write8(UCSR0B, 0);
}

fn uint Uart.baud(self) {
    uint ubrr = (uint)(soc::read8(UBRR0H) & 0x0F) << 8 | soc::read8(UBRR0L);
    return rate_for(ubrr, (soc::read8(UCSR0A) & U2X0) != 0);
}

fn void Uart.write_byte(self, char byte) {
    while ((soc::read8(UCSR0A) & UDRE0) == 0) {}
    // Queue the byte, then clear TXC0 (write one, keep U2X0, error flags
    // written as zero). In this order, and with interrupts off, a TXC0 left
    // over from the previous byte cannot make `flush()` return early.
    irq::@critical() {
        soc::write8(UDR0, byte);
        soc::write8(UCSR0A, (soc::read8(UCSR0A) & U2X0) | TXC0);
        tx_pending = true;
    };
}

fn void Uart.write(self, char[] bytes) {
    foreach (byte : bytes) self.write_byte(byte);
}

fn void Uart.flush(self) {
    if (!tx_pending) return;
    while ((soc::read8(UCSR0A) & TXC0) == 0) {}
    tx_pending = false;
}

fn bool Uart.can_read(self) => (soc::read8(UCSR0A) & RXC0) != 0;

fn char? Uart.try_read(self) {
    char status = soc::read8(UCSR0A);
    if ((status & RXC0) == 0) return NO_DATA~;
    // The error flags belong to the byte at the head of the FIFO, so they
    // must be read before UDR0.
    char byte = soc::read8(UDR0);
    if (status & FE0) return FRAMING_ERROR~;
    if (status & DOR0) return OVERRUN~;
    if (status & UPE0) return PARITY_ERROR~;
    return byte;
}
