module embedded::spi @feat(MCU_ATMEGA328P);

import embedded::core;
import embedded::gpio;
import embedded::backends::avr::atmega328p::soc;
import embedded::backends::avr::atmega328p::regs;



const gpio::Pin SS_PIN   = (gpio::Pin)10;
const gpio::Pin MOSI_PIN = (gpio::Pin)11;
const gpio::Pin MISO_PIN = (gpio::Pin)12;
const gpio::Pin SCK_PIN  = (gpio::Pin)13;

struct Bus {
    char spcr;
}

fn Bus? open(Config config = {}) => open_pins(SCK_PIN, MOSI_PIN, MISO_PIN, config);

fn Bus? open_pins(gpio::Pin sck, gpio::Pin mosi, gpio::Pin miso, Config config = {}) {
    if (sck != SCK_PIN || mosi != MOSI_PIN || miso != MISO_PIN) return INVALID_PINS~;
    uint hz = config.frequency_hz == 0 ? DEFAULT_HZ : config.frequency_hz;

    // Dividers 2, 4, ..., 128: take the smallest whose rate is not above hz.
    uint divider = 2;
    while (divider < 128 && soc::CPU_HZ / divider > hz) divider *= 2;
    if (soc::CPU_HZ / divider > hz) return UNSUPPORTED_FREQUENCY~;
    // SPR1:0 select /4, /16, /64, /128; SPI2X halves the first three.
    char spr;
    bool double_speed;
    switch (divider) {
        case 2:   spr = 0; double_speed = true;
        case 4:   spr = 0; double_speed = false;
        case 8:   spr = 1; double_speed = true;
        case 16:  spr = 1; double_speed = false;
        case 32:  spr = 2; double_speed = true;
        case 64:  spr = 2; double_speed = false;
        default:  spr = 3; double_speed = false;
    }

    char spcr = regs::SPE | regs::MSTR | spr;
    if (config.bit_order == BitOrder.LSB_FIRST) spcr |= regs::DORD;
    switch (config.mode) {
        case Mode.MODE0: break;
        case Mode.MODE1: spcr |= regs::CPHA;
        case Mode.MODE2: spcr |= regs::CPOL;
        case Mode.MODE3: spcr |= regs::CPOL | regs::CPHA;
        default: return UNSUPPORTED_MODE~;
    }

    // SS high and output first, so the unit cannot drop to slave mode.
    gpio::configure(SS_PIN, gpio::CONFIG_OUTPUT_HIGH)!;
    gpio::configure(SCK_PIN, (spcr & regs::CPOL) ? gpio::CONFIG_OUTPUT_HIGH : gpio::CONFIG_OUTPUT_LOW)!;
    gpio::configure(MOSI_PIN, gpio::CONFIG_OUTPUT_LOW)!;
    gpio::configure(MISO_PIN, gpio::CONFIG_INPUT)!;
    @reg_write(regs::SPSR, double_speed ? regs::SPI2X : 0);
    @reg_write(regs::SPCR, spcr);
    return { spcr };
}

fn void Bus.close(self) {
    @reg_write(regs::SPCR, 0);
    (void)gpio::reset(SCK_PIN);
    (void)gpio::reset(MOSI_PIN);
}

fn uint Bus.frequency(self) {
    uint divider;
    switch (self.spcr & regs::SPR_MASK) {
        case 0: divider = 4;
        case 1: divider = 16;
        case 2: divider = 64;
        default: divider = 128;
    }
    if ((@reg_read(regs::SPSR) & regs::SPI2X) != 0 && divider != 128) divider /= 2;
    return soc::CPU_HZ / divider;
}

fn char Bus.transfer_byte(self, char byte) {
    @reg_write(regs::SPDR, byte);
    while ((@reg_read(regs::SPSR) & regs::SPIF) == 0) {}
    return @reg_read(regs::SPDR);
}

fn void? Bus.transfer(self, char[] tx, char[] rx) {
    if (tx.len > 0 && rx.len > 0 && tx.len != rx.len) return INVALID_LENGTH~;
    usz len = tx.len > 0 ? tx.len : rx.len;
    for (usz i = 0; i < len; i++) {
        char received = self.transfer_byte(tx.len > 0 ? tx[i] : 0xFF);
        if (rx.len > 0) rx[i] = received;
    }
}

fn void Bus.write(self, char[] data) {
    foreach (byte : data) (void)self.transfer_byte(byte);
}

fn void Bus.read(self, char[] buffer, char fill = 0xFF) {
    foreach (&byte : buffer) *byte = self.transfer_byte(fill);
}
