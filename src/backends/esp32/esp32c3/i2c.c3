module embedded::i2c;

import embedded::gpio;
import embedded::time;
import embedded::board;
import embedded::backends::esp32::esp32c3::soc;

// I2C0 in master mode. The controller runs a list of up to 8 commands
// (RSTART, WRITE n, READ n, STOP, END) against a 32-byte FIFO. Longer
// transfers are split with END, which pauses the bus (SCL held low) until the
// FIFO is refilled or drained and the next command list is started. Timing
// follows ESP-IDF v5.3's i2c_ll_master_cal_bus_clk.
const uint I2C_BASE = 0x6001_3000;
const uint SCL_LOW_PERIOD   = I2C_BASE + 0x00;
const uint CTR              = I2C_BASE + 0x04;
const uint TO               = I2C_BASE + 0x0C;
const uint FIFO_CONF        = I2C_BASE + 0x18;
const uint DATA             = I2C_BASE + 0x1C;
const uint INT_RAW          = I2C_BASE + 0x20;
const uint INT_CLR          = I2C_BASE + 0x24;
const uint SDA_HOLD         = I2C_BASE + 0x30;
const uint SDA_SAMPLE       = I2C_BASE + 0x34;
const uint SCL_HIGH_PERIOD  = I2C_BASE + 0x38;
const uint SCL_START_HOLD   = I2C_BASE + 0x40;
const uint SCL_RSTART_SETUP = I2C_BASE + 0x44;
const uint SCL_STOP_HOLD    = I2C_BASE + 0x48;
const uint SCL_STOP_SETUP   = I2C_BASE + 0x4C;
const uint FILTER_CFG       = I2C_BASE + 0x50;
const uint CLK_CONF         = I2C_BASE + 0x54;
const uint COMD0            = I2C_BASE + 0x58;

// CTR
const uint CTR_CONF_UPGATE = 1u << 11;
const uint CTR_FSM_RST     = 1u << 10;
const uint CTR_CLK_EN      = 1u << 8;
const uint CTR_TRANS_START = 1u << 5;
const uint CTR_MS_MODE     = 1u << 4;
const uint CTR_SCL_FORCE_OUT = 1u << 1;
const uint CTR_SDA_FORCE_OUT = 1u << 0;
const uint CTR_MASTER = CTR_MS_MODE | CTR_CLK_EN | CTR_SCL_FORCE_OUT | CTR_SDA_FORCE_OUT;
// FIFO_CONF
const uint FIFO_TX_RST = 1u << 13;
const uint FIFO_RX_RST = 1u << 12;
// INT_RAW / INT_CLR
const uint INT_NACK           = 1u << 10;
const uint INT_TIME_OUT       = 1u << 8;
const uint INT_TRANS_COMPLETE = 1u << 7;
const uint INT_ARB_LOST       = 1u << 5;
const uint INT_END_DETECT     = 1u << 3;
// CLK_CONF
const uint CLK_SCLK_ACTIVE = 1u << 21;
// TO
const uint TO_ENABLE = 1u << 5;
// FILTER_CFG: both filters on, threshold 7 source clocks (ESP-IDF default).
const uint FILTER_VALUE = (1u << 9) | (1u << 8) | (7u << 4) | 7u;

// Command word: op_code[13:11] ack_val[10] ack_exp[9] ack_en[8] byte_num[7:0].
const uint OP_WRITE   = 1;
const uint OP_STOP    = 2;
const uint OP_READ    = 3;
const uint OP_END     = 4;
const uint OP_RSTART  = 6;
const uint CMD_ACK_VAL_NACK = 1u << 10;
const uint CMD_ACK_EN = 1u << 8;

const uint FIFO_SIZE = 32;
const uint SIGNAL_SCL = 53; // I2CEXT0_SCL_IN/OUT_IDX
const uint SIGNAL_SDA = 54; // I2CEXT0_SDA_IN/OUT_IDX
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
    soc::enable_peripheral(soc::PERIP_I2C_EXT0);
    soc::write(CTR, CTR_MASTER);
    soc::write(FIFO_CONF, FIFO_TX_RST | FIFO_RX_RST);
    soc::write(FIFO_CONF, 0);

    uint clkm_div = soc::XTAL_HZ / (hz * 1024) + 1;
    uint half_cycle = soc::XTAL_HZ / clkm_div / hz / 2;
    uint wait_high = hz >= 80_000 ? half_cycle / 2 - 2 : half_cycle / 4;
    // Timeout field is log2 of the timeout in source clocks; ESP-IDF uses
    // about ten bus cycles.
    uint tout = 2;
    for (uint v = 5 * half_cycle; v != 0; v >>= 1) tout++;

    soc::write(CLK_CONF, CLK_SCLK_ACTIVE | (clkm_div - 1)); // source: XTAL
    soc::write(SCL_LOW_PERIOD, half_cycle - 1);
    soc::write(SCL_HIGH_PERIOD, (wait_high << 9) | (half_cycle - wait_high));
    soc::write(SDA_HOLD, half_cycle / 4 - 1);
    soc::write(SDA_SAMPLE, half_cycle / 2 - 1);
    soc::write(SCL_RSTART_SETUP, half_cycle - 1);
    soc::write(SCL_STOP_SETUP, half_cycle - 1);
    soc::write(SCL_START_HOLD, half_cycle - 1);
    soc::write(SCL_STOP_HOLD, half_cycle - 1);
    soc::write(TO, TO_ENABLE | (tout > 31 ? 31 : tout));
    soc::write(FILTER_CFG, FILTER_VALUE);
    soc::set_bits(CTR, CTR_CONF_UPGATE);
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
    soc::route_output(scl, SIGNAL_SCL, open_drain: true, pull_up: true);
    soc::route_input(SIGNAL_SCL, scl, pull_up: true);
    soc::route_output(sda, SIGNAL_SDA, open_drain: true, pull_up: true);
    soc::route_input(SIGNAL_SDA, sda, pull_up: true);
    return { hz, config.timeout_us == 0 ? DEFAULT_TIMEOUT_US : config.timeout_us };
}

fn void Bus.close(self) {
    soc::disable_peripheral(soc::PERIP_I2C_EXT0);
    soc::release_pin(bus_sda);
    soc::release_pin(bus_scl);
}

fn uint Bus.frequency(self) {
    uint clkm_div = (soc::read(CLK_CONF) & 0xFF) + 1;
    uint period = (soc::read(SCL_LOW_PERIOD) & 0x1FF) + 1 + (soc::read(SCL_HIGH_PERIOD) & 0x1FF)
        + ((soc::read(SCL_HIGH_PERIOD) >> 9) & 0x7F);
    return soc::XTAL_HZ / clkm_div / period;
}

fn uint cmd(uint op, uint bytes = 0, uint flags = 0) @local => (op << 11) | flags | bytes;

// Runs the command list loaded in COMD0.. and waits for STOP (`last`) or END.
fn void? run(bool last, time::Instant deadline) @local {
    soc::write(INT_CLR, 0xFFFF_FFFF);
    soc::set_bits(CTR, CTR_CONF_UPGATE);
    soc::set_bits(CTR, CTR_TRANS_START);
    uint done = last ? INT_TRANS_COMPLETE : INT_END_DETECT;
    while (true) {
        uint raw = soc::read(INT_RAW);
        if (raw & INT_NACK) return DATA_NACK~;
        if (raw & INT_ARB_LOST) return ARBITRATION_LOST~;
        if (raw & INT_TIME_OUT) return TIMEOUT~;
        if (raw & done) return;
        if (time::has_elapsed(deadline)) return TIMEOUT~;
    }
}

// Writes the address byte and `data` in FIFO-sized pieces. On return the bus
// is paused after an END (`hold`) or stopped.
fn void? write_phase(char address, char[] data, bool hold, time::Instant deadline) @local {
    soc::write(DATA, (uint)address << 1);
    usz sent = 0;
    usz chunk = data.len < FIFO_SIZE - 1 ? data.len : FIFO_SIZE - 1;
    for (usz i = 0; i < chunk; i++) soc::write(DATA, data[i]);
    sent = chunk;

    soc::write(COMD0, cmd(OP_RSTART));
    // The address byte is checked separately so a missing device is
    // reported as ADDRESS_NACK, not DATA_NACK.
    soc::write(COMD0 + 4, cmd(OP_WRITE, 1, CMD_ACK_EN));
    if (catch err = run_address(deadline)) return err~;

    while (true) {
        bool more = sent < data.len;
        uint n = (uint)chunk;
        uint index = 0;
        if (n > 0) soc::write(COMD0 + 4 * index++, cmd(OP_WRITE, n, CMD_ACK_EN));
        bool last = !more && !hold;
        soc::write(COMD0 + 4 * index, cmd(last ? OP_STOP : OP_END));
        run(last, deadline)!;
        if (!more) return;
        chunk = data.len - sent < FIFO_SIZE ? data.len - sent : FIFO_SIZE;
        for (usz i = 0; i < chunk; i++) soc::write(DATA, data[sent + i]);
        sent += chunk;
    }
}

// Sends START + address (already in the FIFO, commands 0 and 1 loaded) and
// pauses with END, mapping a NACK to ADDRESS_NACK.
fn void? run_address(time::Instant deadline) @local {
    soc::write(COMD0 + 8, cmd(OP_END));
    if (catch err = run(false, deadline)) {
        return err == DATA_NACK ? ADDRESS_NACK~ : err~;
    }
}

fn void? read_phase(char address, char[] buffer, time::Instant deadline) @local {
    soc::write(DATA, ((uint)address << 1) | 1);
    soc::write(COMD0, cmd(OP_RSTART));
    soc::write(COMD0 + 4, cmd(OP_WRITE, 1, CMD_ACK_EN));
    run_address(deadline)!;

    usz received = 0;
    while (received < buffer.len) {
        usz chunk = buffer.len - received < FIFO_SIZE ? buffer.len - received : FIFO_SIZE;
        bool last = received + chunk == buffer.len;
        uint index = 0;
        if (last) {
            // ACK all but the final byte, NACK it, then STOP.
            if (chunk > 1) soc::write(COMD0 + 4 * index++, cmd(OP_READ, (uint)chunk - 1));
            soc::write(COMD0 + 4 * index++, cmd(OP_READ, 1, CMD_ACK_VAL_NACK));
            soc::write(COMD0 + 4 * index, cmd(OP_STOP));
        } else {
            soc::write(COMD0 + 4 * index++, cmd(OP_READ, (uint)chunk));
            soc::write(COMD0 + 4 * index, cmd(OP_END));
        }
        run(last, deadline)!;
        for (usz i = 0; i < chunk; i++) buffer[received + i] = (char)soc::read(DATA);
        received += chunk;
    }
}

// Puts the controller back into a usable state after a failed transaction.
fn void recover(uint hz) @local {
    soc::set_bits(CTR, CTR_FSM_RST);
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
    soc::write(FIFO_CONF, FIFO_TX_RST | FIFO_RX_RST);
    soc::write(FIFO_CONF, 0);
    if (data.len > 0 || !has_read) write_phase(address, data, has_read, deadline)!;
    if (has_read) read_phase(address, buffer, deadline)!;
}

fn void? Bus.write(self, char address, char[] data) => self.write_read(address, data, {});
fn void? Bus.read(self, char address, char[] buffer) => self.write_read(address, {}, buffer);

fn bool Bus.probe(self, char address) {
    if (catch self.write_read(address, {}, {})) return false;
    return true;
}
