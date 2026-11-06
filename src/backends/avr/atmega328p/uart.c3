module embedded::uart @feat(MCU_ATMEGA328P);

import embedded::gpio;
import embedded::irq;
import embedded::backends::avr::atmega328p::soc;
import embedded::backends::avr::atmega328p::regs;

// USART0, the ATmega328P's only UART: TX on PD1 (D1), RX on PD0 (D0).
// Enabling the transmitter and receiver takes the pins over from GPIO.
constdef Port : inline char {
    UART0 = 0,
}



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
    char frame = (char)((3 - (char)config.data_bits) << regs::UCSZ0_SHIFT);
    switch (config.parity) {
        case Parity.NONE: break;
        case Parity.EVEN: frame |= regs::UPM01;
        case Parity.ODD:  frame |= regs::UPM01 | regs::UPM00;
        default: return UNSUPPORTED_FORMAT~;
    }
    if (config.stop_bits == StopBits.TWO) frame |= regs::USBS0;

    soc::write8(regs::UCSR0B, 0);
    soc::write8(regs::UCSR0A, double_speed ? regs::U2X0 : 0);
    soc::write8(regs::UBRR0H, (char)(ubrr >> 8));
    soc::write8(regs::UBRR0L, (char)ubrr);
    soc::write8(regs::UCSR0C, frame);
    soc::write8(regs::UCSR0B, regs::RXEN0 | regs::TXEN0);
    tx_pending = false;
    return { port };
}

fn void Uart.close(self) {
    self.flush();
    soc::write8(regs::UCSR0B, 0);
}

fn uint Uart.baud(self) {
    uint ubrr = (uint)(soc::read8(regs::UBRR0H) & regs::UBRR0H_MASK) << 8 | soc::read8(regs::UBRR0L);
    return rate_for(ubrr, (soc::read8(regs::UCSR0A) & regs::U2X0) != 0);
}

fn void Uart.write_byte(self, char byte) {
    while ((soc::read8(regs::UCSR0A) & regs::UDRE0) == 0) {}
    // Queue the byte, then clear TXC0 (write one, keep U2X0, error flags
    // written as zero). In this order, and with interrupts off, a TXC0 left
    // over from the previous byte cannot make `flush()` return early.
    irq::@critical() {
        soc::write8(regs::UDR0, byte);
        soc::write8(regs::UCSR0A, (soc::read8(regs::UCSR0A) & regs::U2X0) | regs::TXC0);
        tx_pending = true;
    };
}

fn void Uart.write(self, char[] bytes) {
    foreach (byte : bytes) self.write_byte(byte);
}

fn void Uart.flush(self) {
    if (!tx_pending) return;
    while ((soc::read8(regs::UCSR0A) & regs::TXC0) == 0) {}
    tx_pending = false;
}

fn bool Uart.can_read(self) => (soc::read8(regs::UCSR0A) & regs::RXC0) != 0;

fn char? Uart.try_read(self) {
    char status = soc::read8(regs::UCSR0A);
    if ((status & regs::RXC0) == 0) return NO_DATA~;
    // The error flags belong to the byte at the head of the FIFO, so they
    // must be read before UDR0.
    char byte = soc::read8(regs::UDR0);
    if (status & regs::FE0) return FRAMING_ERROR~;
    if (status & regs::DOR0) return OVERRUN~;
    if (status & regs::UPE0) return PARITY_ERROR~;
    return byte;
}
