module embedded::i2c @feat(MCU_ATMEGA328P);

import embedded::gpio;
import embedded::time;
import embedded::backends::avr::atmega328p::soc;
import embedded::backends::avr::atmega328p::regs;

// TWI: SDA on PC4 (A4), SCL on PC5 (A5).



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
    soc::write8(regs::TWSR, twps);
    soc::write8(regs::TWBR, (char)twbr);
    soc::write8(regs::TWCR, regs::TWEN);
    return { config.timeout_us == 0 ? DEFAULT_TIMEOUT_US : config.timeout_us };
}

fn void Bus.close(self) {
    soc::write8(regs::TWCR, 0);
    (void)gpio::reset(SDA_PIN);
    (void)gpio::reset(SCL_PIN);
}

fn uint Bus.frequency(self) {
    uint scale = 1;
    for (char twps = soc::read8(regs::TWSR) & regs::TWPS_MASK; twps > 0; twps--) scale *= 4;
    return soc::CPU_HZ / (16 + 2 * (uint)soc::read8(regs::TWBR) * scale);
}

// Starts a TWI action and waits for it; returns the status code.
fn char? step(char control, time::Instant deadline) @local {
    soc::write8(regs::TWCR, control | regs::TWINT | regs::TWEN);
    while ((soc::read8(regs::TWCR) & regs::TWINT) == 0) {
        if (time::has_elapsed(deadline)) {
            // Disabling the unit releases both lines and resets its state.
            soc::write8(regs::TWCR, 0);
            soc::write8(regs::TWCR, regs::TWEN);
            return TIMEOUT~;
        }
    }
    return soc::read8(regs::TWSR) & regs::TW_STATUS_MASK;
}

fn void stop(time::Instant deadline) @local {
    soc::write8(regs::TWCR, regs::TWINT | regs::TWEN | regs::TWSTO);
    // TWSTO clears once the STOP condition is on the bus.
    while ((soc::read8(regs::TWCR) & regs::TWSTO) != 0) {
        if (time::has_elapsed(deadline)) {
            soc::write8(regs::TWCR, 0);
            soc::write8(regs::TWCR, regs::TWEN);
            return;
        }
    }
}

fn void? start_and_address(char address, bool read, time::Instant deadline) @local {
    char status = step(regs::TWSTA, deadline)!;
    if (status == regs::TW_ARB_LOST) return ARBITRATION_LOST~;
    if (status != regs::TW_START && status != regs::TW_REP_START) return BUS_ERROR~;
    soc::write8(regs::TWDR, (char)(address << 1) | (read ? 1 : 0));
    status = step(0, deadline)!;
    switch (status) {
        case regs::TW_MT_SLA_ACK:
        case regs::TW_MR_SLA_ACK:
            return;
        case regs::TW_MT_SLA_NACK:
        case regs::TW_MR_SLA_NACK:
            return ADDRESS_NACK~;
        case regs::TW_ARB_LOST:
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
            soc::write8(regs::TWDR, byte);
            char status = step(0, deadline)!;
            if (status == regs::TW_MT_DATA_NACK) return DATA_NACK~;
            if (status == regs::TW_ARB_LOST) return ARBITRATION_LOST~;
            if (status != regs::TW_MT_DATA_ACK) return BUS_ERROR~;
        }
    }
    if (buffer.len > 0) {
        start_and_address(address, true, deadline)!;
        foreach (i, &byte : buffer) {
            bool last = i + 1 == buffer.len;
            // ACK every byte but the last, which tells the device to stop.
            char status = step(last ? 0 : regs::TWEA, deadline)!;
            if (status != (last ? regs::TW_MR_DATA_NACK : regs::TW_MR_DATA_ACK)) return BUS_ERROR~;
            *byte = soc::read8(regs::TWDR);
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
