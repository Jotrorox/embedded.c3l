module embedded::i2c;

import embedded::gpio;
import embedded::time;
import embedded::board;
import embedded::backends::esp32::esp32c3::soc;
import embedded::backends::esp32::esp32c3::regs;

// I2C0 in master mode. The controller runs a list of up to 8 commands
// (RSTART, WRITE n, READ n, STOP, END) against a 32-byte FIFO. Longer
// transfers are split with END, which pauses the bus (SCL held low) until the
// FIFO is refilled or drained and the next command list is started. Timing
// follows ESP-IDF v5.3's i2c_ll_master_cal_bus_clk.
const uint CTR_MASTER = regs::I2C_CTR_MS_MODE | regs::I2C_CTR_CLK_EN
    | regs::I2C_CTR_SCL_FORCE_OUT | regs::I2C_CTR_SDA_FORCE_OUT;
// Both glitch filters on, threshold 7 source clocks (ESP-IDF default).
const uint FILTER_VALUE = regs::I2C_FILTER_SDA_EN | regs::I2C_FILTER_SCL_EN
    | (7u << regs::I2C_FILTER_SDA_THRES_SHIFT) | (7u << regs::I2C_FILTER_SCL_THRES_SHIFT);

const uint FIFO_SIZE = 32;
const uint MAX_HZ = 1_000_000;
const uint MIN_HZ = 10_000;

struct Bus {
    uint frequency_hz;
    uint timeout_us;
}

gpio::Pin bus_sda @local;
gpio::Pin bus_scl @local;

fn Bus? open(Config config = {}) => open_pins(board::I2C_SDA, board::I2C_SCL, config);

fn void configure(uint hz) @local {
    soc::enable_peripheral(regs::PERIP_I2C_EXT0);
    soc::write(regs::I2C_CTR, CTR_MASTER);
    soc::write(regs::I2C_FIFO_CONF, regs::I2C_FIFO_TX_RST | regs::I2C_FIFO_RX_RST);
    soc::write(regs::I2C_FIFO_CONF, 0);

    uint clkm_div = soc::XTAL_HZ / (hz * 1024) + 1;
    uint half_cycle = soc::XTAL_HZ / clkm_div / hz / 2;
    uint wait_high = hz >= 80_000 ? half_cycle / 2 - 2 : half_cycle / 4;
    // Timeout field is log2 of the timeout in source clocks; ESP-IDF uses
    // about ten bus cycles.
    uint tout = 2;
    for (uint v = 5 * half_cycle; v != 0; v >>= 1) tout++;

    soc::write(regs::I2C_CLK_CONF, regs::I2C_CLK_CONF_SCLK_ACTIVE | (clkm_div - 1)); // source: XTAL
    soc::write(regs::I2C_SCL_LOW_PERIOD, half_cycle - 1);
    soc::write(regs::I2C_SCL_HIGH_PERIOD, (wait_high << regs::I2C_SCL_WAIT_HIGH_PERIOD_SHIFT) | (half_cycle - wait_high));
    soc::write(regs::I2C_SDA_HOLD, half_cycle / 4 - 1);
    soc::write(regs::I2C_SDA_SAMPLE, half_cycle / 2 - 1);
    soc::write(regs::I2C_SCL_RSTART_SETUP, half_cycle - 1);
    soc::write(regs::I2C_SCL_STOP_SETUP, half_cycle - 1);
    soc::write(regs::I2C_SCL_START_HOLD, half_cycle - 1);
    soc::write(regs::I2C_SCL_STOP_HOLD, half_cycle - 1);
    soc::write(regs::I2C_TO, regs::I2C_TO_ENABLE | (tout > regs::I2C_TO_VALUE_MASK ? regs::I2C_TO_VALUE_MASK : tout));
    soc::write(regs::I2C_FILTER_CFG, FILTER_VALUE);
    soc::set_bits(regs::I2C_CTR, regs::I2C_CTR_CONF_UPGATE);
}

fn Bus? open_pins(gpio::Pin sda, gpio::Pin scl, Config config = {}) {
    if (!gpio::is_valid(sda) || !gpio::is_valid(scl) || sda == scl) return INVALID_PINS~;
    uint hz = config.frequency_hz == 0 ? STANDARD_HZ : config.frequency_hz;
    if (hz < MIN_HZ || hz > MAX_HZ) return UNSUPPORTED_FREQUENCY~;

    configure(hz);
    bus_sda = sda;
    bus_scl = scl;
    // Open drain with pull-up; the controller reads both lines back for
    // clock stretching and arbitration.
    soc::route_output(scl, regs::SIG_I2CEXT0_SCL, open_drain: true, pull_up: true);
    soc::route_input(regs::SIG_I2CEXT0_SCL, scl, pull_up: true);
    soc::route_output(sda, regs::SIG_I2CEXT0_SDA, open_drain: true, pull_up: true);
    soc::route_input(regs::SIG_I2CEXT0_SDA, sda, pull_up: true);
    return { hz, config.timeout_us == 0 ? DEFAULT_TIMEOUT_US : config.timeout_us };
}

fn void Bus.close(self) {
    soc::disable_peripheral(regs::PERIP_I2C_EXT0);
    soc::release_pin(bus_sda);
    soc::release_pin(bus_scl);
}

fn uint Bus.frequency(self) {
    uint clkm_div = (soc::read(regs::I2C_CLK_CONF) & regs::I2C_CLK_CONF_SCLK_DIV_NUM_MASK) + 1;
    uint high = soc::read(regs::I2C_SCL_HIGH_PERIOD);
    uint period = (soc::read(regs::I2C_SCL_LOW_PERIOD) & regs::I2C_SCL_LOW_PERIOD_MASK) + 1
        + (high & regs::I2C_SCL_HIGH_PERIOD_MASK)
        + ((high & regs::I2C_SCL_WAIT_HIGH_PERIOD_MASK) >> regs::I2C_SCL_WAIT_HIGH_PERIOD_SHIFT);
    return soc::XTAL_HZ / clkm_div / period;
}

fn uint cmd(uint op, uint bytes = 0, uint flags = 0) @local => (op << regs::I2C_CMD_OP_SHIFT) | flags | bytes;

// Runs the command list loaded in regs::I2C_COMD0.. and waits for STOP (`last`) or END.
fn void? run(bool last, time::Instant deadline) @local {
    soc::write(regs::I2C_INT_CLR, 0xFFFF_FFFF);
    soc::set_bits(regs::I2C_CTR, regs::I2C_CTR_CONF_UPGATE);
    soc::set_bits(regs::I2C_CTR, regs::I2C_CTR_TRANS_START);
    uint done = last ? regs::I2C_INT_TRANS_COMPLETE : regs::I2C_INT_END_DETECT;
    while (true) {
        uint raw = soc::read(regs::I2C_INT_RAW);
        if (raw & regs::I2C_INT_NACK) return DATA_NACK~;
        if (raw & regs::I2C_INT_ARB_LOST) return ARBITRATION_LOST~;
        if (raw & regs::I2C_INT_TIME_OUT) return TIMEOUT~;
        if (raw & done) return;
        if (time::has_elapsed(deadline)) return TIMEOUT~;
    }
}

// Writes the address byte and `data` in FIFO-sized pieces. On return the bus
// is paused after an END (`hold`) or stopped.
fn void? write_phase(char address, char[] data, bool hold, time::Instant deadline) @local {
    soc::write(regs::I2C_DATA, (uint)address << 1);
    usz sent = 0;
    usz chunk = data.len < FIFO_SIZE - 1 ? data.len : FIFO_SIZE - 1;
    for (usz i = 0; i < chunk; i++) soc::write(regs::I2C_DATA, data[i]);
    sent = chunk;

    soc::write(regs::I2C_COMD0, cmd(regs::I2C_OP_RSTART));
    // The address byte is checked separately so a missing device is
    // reported as ADDRESS_NACK, not DATA_NACK.
    soc::write(regs::I2C_COMD0 + 4, cmd(regs::I2C_OP_WRITE, 1, regs::I2C_CMD_ACK_EN));
    if (catch err = run_address(deadline)) return err~;

    while (true) {
        bool more = sent < data.len;
        uint n = (uint)chunk;
        uint index = 0;
        if (n > 0) soc::write(regs::I2C_COMD0 + 4 * index++, cmd(regs::I2C_OP_WRITE, n, regs::I2C_CMD_ACK_EN));
        bool last = !more && !hold;
        soc::write(regs::I2C_COMD0 + 4 * index, cmd(last ? regs::I2C_OP_STOP : regs::I2C_OP_END));
        run(last, deadline)!;
        if (!more) return;
        chunk = data.len - sent < FIFO_SIZE ? data.len - sent : FIFO_SIZE;
        for (usz i = 0; i < chunk; i++) soc::write(regs::I2C_DATA, data[sent + i]);
        sent += chunk;
    }
}

// Sends START + address (already in the FIFO, commands 0 and 1 loaded) and
// pauses with END, mapping a NACK to ADDRESS_NACK.
fn void? run_address(time::Instant deadline) @local {
    soc::write(regs::I2C_COMD0 + 8, cmd(regs::I2C_OP_END));
    if (catch err = run(false, deadline)) {
        return err == DATA_NACK ? ADDRESS_NACK~ : err~;
    }
}

fn void? read_phase(char address, char[] buffer, time::Instant deadline) @local {
    soc::write(regs::I2C_DATA, ((uint)address << 1) | 1);
    soc::write(regs::I2C_COMD0, cmd(regs::I2C_OP_RSTART));
    soc::write(regs::I2C_COMD0 + 4, cmd(regs::I2C_OP_WRITE, 1, regs::I2C_CMD_ACK_EN));
    run_address(deadline)!;

    usz received = 0;
    while (received < buffer.len) {
        usz chunk = buffer.len - received < FIFO_SIZE ? buffer.len - received : FIFO_SIZE;
        bool last = received + chunk == buffer.len;
        uint index = 0;
        if (last) {
            // ACK all but the final byte, NACK it, then STOP.
            if (chunk > 1) soc::write(regs::I2C_COMD0 + 4 * index++, cmd(regs::I2C_OP_READ, (uint)chunk - 1));
            soc::write(regs::I2C_COMD0 + 4 * index++, cmd(regs::I2C_OP_READ, 1, regs::I2C_CMD_ACK_VAL_NACK));
            soc::write(regs::I2C_COMD0 + 4 * index, cmd(regs::I2C_OP_STOP));
        } else {
            soc::write(regs::I2C_COMD0 + 4 * index++, cmd(regs::I2C_OP_READ, (uint)chunk));
            soc::write(regs::I2C_COMD0 + 4 * index, cmd(regs::I2C_OP_END));
        }
        run(last, deadline)!;
        for (usz i = 0; i < chunk; i++) buffer[received + i] = (char)soc::read(regs::I2C_DATA);
        received += chunk;
    }
}

// Puts the controller back into a usable state after a failed transaction.
fn void recover(uint hz) @local {
    soc::set_bits(regs::I2C_CTR, regs::I2C_CTR_FSM_RST);
    configure(hz);
}

fn void? Bus.write_read(self, char address, char[] data, char[] buffer) {
    if (address > 0x7F) return INVALID_ADDRESS~;
    time::Instant deadline = time::deadline_after(time::us(self.timeout_us));
    bool has_read = buffer.len > 0;
    if (catch err = transfer(address, data, buffer, has_read, deadline)) {
        recover(self.frequency_hz);
        return err~;
    }
}

fn void? transfer(char address, char[] data, char[] buffer, bool has_read, time::Instant deadline) @local {
    // Both FIFOs are empty between phases (END only pauses once the TX FIFO
    // is drained and the RX FIFO is read out), so one reset per transaction
    // is enough.
    soc::write(regs::I2C_FIFO_CONF, regs::I2C_FIFO_TX_RST | regs::I2C_FIFO_RX_RST);
    soc::write(regs::I2C_FIFO_CONF, 0);
    if (data.len > 0 || !has_read) write_phase(address, data, has_read, deadline)!;
    if (has_read) read_phase(address, buffer, deadline)!;
}

fn void? Bus.write(self, char address, char[] data) => self.write_read(address, data, {});
fn void? Bus.read(self, char address, char[] buffer) => self.write_read(address, {}, buffer);

fn bool Bus.probe(self, char address) {
    if (catch self.write_read(address, {}, {})) return false;
    return true;
}
