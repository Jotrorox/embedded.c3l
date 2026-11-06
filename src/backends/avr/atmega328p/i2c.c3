module embedded::i2c;

import embedded::gpio;
import embedded::time;
import embedded::backends::avr::atmega328p::soc;

// TWI: SDA on PC4 (A4), SCL on PC5 (A5).
const uint TWBR = 0xB8;
const uint TWSR = 0xB9;
const uint TWDR = 0xBB;
const uint TWCR = 0xBC;

const char TWINT = 1 << 7;
const char TWEA  = 1 << 6;
const char TWSTA = 1 << 5;
const char TWSTO = 1 << 4;
const char TWEN  = 1 << 2;

// TWSR status codes (prescaler bits masked off).
const char STATUS_MASK         = 0xF8;
const char STATUS_START        = 0x08;
const char STATUS_REP_START    = 0x10;
const char STATUS_SLA_W_ACK    = 0x18;
const char STATUS_SLA_W_NACK   = 0x20;
const char STATUS_DATA_W_ACK   = 0x28;
const char STATUS_DATA_W_NACK  = 0x30;
const char STATUS_ARB_LOST     = 0x38;
const char STATUS_SLA_R_ACK    = 0x40;
const char STATUS_SLA_R_NACK   = 0x48;
const char STATUS_DATA_R_ACK   = 0x50;
const char STATUS_DATA_R_NACK  = 0x58;

const gpio::Pin SDA_PIN = (gpio::Pin)18;
const gpio::Pin SCL_PIN = (gpio::Pin)19;

struct Bus {
    uint timeout_us;
}

fn Bus? open(Config config = {}) => open_pins(SDA_PIN, SCL_PIN, config);

// SCL = CPU / (16 + 2 * TWBR * 4^TWPS). Picks the smallest prescaler that
// fits TWBR into 8 bits.
fn Bus? open_pins(gpio::Pin sda, gpio::Pin scl, Config config = {}) {
    if (sda != SDA_PIN || scl != SCL_PIN) return INVALID_PINS~;
    uint hz = config.frequency_hz == 0 ? STANDARD_HZ : config.frequency_hz;
    if (hz > FAST_HZ || hz == 0) return UNSUPPORTED_FREQUENCY~;

    uint cycles = soc::CPU_HZ / hz;
    if (cycles < 16 + 2) return UNSUPPORTED_FREQUENCY~;
    char twps = 0;
    uint scale = 1; // 4^TWPS
    uint twbr = (cycles - 16) / 2;
    while (twbr > 255 && twps < 3) {
        twps++;
        scale *= 4;
        twbr = (cycles - 16) / (2 * scale);
    }
    if (twbr > 255) return UNSUPPORTED_FREQUENCY~;

    // Internal pull-ups, as the Arduino Wire library does.
    gpio::configure(sda, gpio::CONFIG_INPUT_PULLUP)!;
    gpio::configure(scl, gpio::CONFIG_INPUT_PULLUP)!;
    soc::write8(TWSR, twps);
    soc::write8(TWBR, (char)twbr);
    soc::write8(TWCR, TWEN);
    return { config.timeout_us == 0 ? DEFAULT_TIMEOUT_US : config.timeout_us };
}

fn void Bus.close(self) {
    soc::write8(TWCR, 0);
    (void)gpio::reset(SDA_PIN);
    (void)gpio::reset(SCL_PIN);
}

fn uint Bus.frequency(self) {
    uint scale = 1;
    for (char twps = soc::read8(TWSR) & 0x03; twps > 0; twps--) scale *= 4;
    return soc::CPU_HZ / (16 + 2 * (uint)soc::read8(TWBR) * scale);
}

// Starts a TWI action and waits for it; returns the status code.
fn char? step(char control, time::Instant deadline) @local {
    soc::write8(TWCR, control | TWINT | TWEN);
    while ((soc::read8(TWCR) & TWINT) == 0) {
        if (time::has_elapsed(deadline)) {
            // Disabling the unit releases both lines and resets its state.
            soc::write8(TWCR, 0);
            soc::write8(TWCR, TWEN);
            return TIMEOUT~;
        }
    }
    return soc::read8(TWSR) & STATUS_MASK;
}

fn void stop(time::Instant deadline) @local {
    soc::write8(TWCR, TWINT | TWEN | TWSTO);
    // TWSTO clears once the STOP condition is on the bus.
    while ((soc::read8(TWCR) & TWSTO) != 0) {
        if (time::has_elapsed(deadline)) {
            soc::write8(TWCR, 0);
            soc::write8(TWCR, TWEN);
            return;
        }
    }
}

fn void? start_and_address(char address, bool read, time::Instant deadline) @local {
    char status = step(TWSTA, deadline)!;
    if (status == STATUS_ARB_LOST) return ARBITRATION_LOST~;
    if (status != STATUS_START && status != STATUS_REP_START) return BUS_ERROR~;
    soc::write8(TWDR, (char)(address << 1) | (read ? 1 : 0));
    status = step(0, deadline)!;
    switch (status) {
        case STATUS_SLA_W_ACK:
        case STATUS_SLA_R_ACK:
            return;
        case STATUS_SLA_W_NACK:
        case STATUS_SLA_R_NACK:
            return ADDRESS_NACK~;
        case STATUS_ARB_LOST:
            return ARBITRATION_LOST~;
        default:
            return BUS_ERROR~;
    }
}

fn void? transfer(char address, char[] data, char[] buffer, time::Instant deadline) @local {
    if (address > 0x7F) return INVALID_ADDRESS~;
    if (data.len > 0 || buffer.len == 0) {
        start_and_address(address, false, deadline)!;
        foreach (byte : data) {
            soc::write8(TWDR, byte);
            char status = step(0, deadline)!;
            if (status == STATUS_DATA_W_NACK) return DATA_NACK~;
            if (status == STATUS_ARB_LOST) return ARBITRATION_LOST~;
            if (status != STATUS_DATA_W_ACK) return BUS_ERROR~;
        }
    }
    if (buffer.len > 0) {
        start_and_address(address, true, deadline)!;
        foreach (i, &byte : buffer) {
            bool last = i + 1 == buffer.len;
            // ACK every byte but the last, which tells the device to stop.
            char status = step(last ? 0 : TWEA, deadline)!;
            if (status != (last ? STATUS_DATA_R_NACK : STATUS_DATA_R_ACK)) return BUS_ERROR~;
            *byte = soc::read8(TWDR);
        }
    }
}

fn void? Bus.write_read(self, char address, char[] data, char[] buffer) {
    time::Instant deadline = time::deadline_after(time::us(self.timeout_us));
    defer stop(deadline);
    transfer(address, data, buffer, deadline)!;
}

fn void? Bus.write(self, char address, char[] data) => self.write_read(address, data, {});
fn void? Bus.read(self, char address, char[] buffer) => self.write_read(address, {}, buffer);

fn bool Bus.probe(self, char address) {
    if (catch self.write_read(address, {}, {})) return false;
    return true;
}
