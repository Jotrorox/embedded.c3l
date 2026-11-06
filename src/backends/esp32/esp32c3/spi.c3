module embedded::spi;

import embedded::gpio;
import embedded::board;
import embedded::backends::esp32::esp32c3::soc;
import embedded::backends::esp32::esp32c3::regs;

// GP-SPI2 as a CPU-driven full-duplex master: up to 64 bytes per hardware
// transaction through the regs::SPI_W0..W15 data buffer. Configuration registers are
// copied into the SPI clock domain by regs::SPI_CMD.UPDATE. Follows ESP-IDF v5.3's
// spi_ll for the ESP32-C3.
// Clock on, master clock on, master clock from XTAL.
const uint CLK_GATE_VALUE = regs::SPI_CLK_GATE_MST_CLK_ACTIVE | regs::SPI_CLK_GATE_CLK_EN;

const uint BUFFER_BYTES = 64;

struct Bus {
    uint frequency_hz;
}

gpio::Pin bus_sck @local;
gpio::Pin bus_mosi @local;

fn Bus? open(Config config = {}) => open_pins(board::SPI_SCK, board::SPI_MOSI, board::SPI_MISO, config);

// Finds the highest clock 40 MHz / (pre * n), pre 1..16, n 2..64, not above
// `hz`, and returns the regs::SPI_CLOCK register value (0 if none fits).
fn uint clock_register(uint hz, uint* actual) @local {
    if (hz >= soc::XTAL_HZ) {
        *actual = soc::XTAL_HZ;
        return regs::SPI_CLOCK_EQU_SYSCLK;
    }
    uint best = 0;
    uint best_pre = 0;
    uint best_n = 0;
    for (uint n = 2; n <= 64; n++) {
        uint pre = (soc::XTAL_HZ + n * hz - 1) / (n * hz);
        if (pre == 0) pre = 1;
        if (pre > 16) continue;
        uint freq = soc::XTAL_HZ / (pre * n);
        if (freq <= hz && freq >= best) {
            best = freq;
            best_pre = pre;
            best_n = n;
        }
    }
    if (best == 0) return 0;
    *actual = best;
    uint high = best_n / 2; // ~50 % duty
    return ((best_pre - 1) << regs::SPI_CLOCK_CLKDIV_PRE_SHIFT) | ((best_n - 1) << regs::SPI_CLOCK_CLKCNT_N_SHIFT)
        | ((high - 1) << regs::SPI_CLOCK_CLKCNT_H_SHIFT) | ((best_n - 1) << regs::SPI_CLOCK_CLKCNT_L_SHIFT);
}

fn void apply_config() @local {
    soc::write(regs::SPI_CMD, regs::SPI_CMD_UPDATE);
    while ((soc::read(regs::SPI_CMD) & regs::SPI_CMD_UPDATE) != 0) {}
}

fn Bus? open_pins(gpio::Pin sck, gpio::Pin mosi, gpio::Pin miso, Config config = {}) {
    if (!gpio::is_valid(sck) || !gpio::is_valid(mosi) || !gpio::is_valid(miso)) return INVALID_PINS~;
    if (sck == mosi || sck == miso || mosi == miso) return INVALID_PINS~;
    uint hz = config.frequency_hz == 0 ? DEFAULT_HZ : config.frequency_hz;
    uint actual;
    uint clock = clock_register(hz, &actual);
    if (clock == 0) return UNSUPPORTED_FREQUENCY~;

    bool cpol;
    bool out_edge;
    switch (config.mode) {
        case Mode.MODE0: cpol = false; out_edge = false;
        case Mode.MODE1: cpol = false; out_edge = true;
        case Mode.MODE2: cpol = true;  out_edge = true;
        case Mode.MODE3: cpol = true;  out_edge = false;
        default: return UNSUPPORTED_MODE~;
    }

    soc::enable_peripheral(regs::PERIP_SPI2);
    soc::write(regs::SPI_CLK_GATE, CLK_GATE_VALUE);
    soc::write(regs::SPI_SLAVE, 0);
    soc::write(regs::SPI_DMA_CONF, 0);
    soc::write(regs::SPI_USER, regs::SPI_USER_DOUTDIN | regs::SPI_USER_USR_MOSI | regs::SPI_USER_USR_MISO | (out_edge ? regs::SPI_USER_CK_OUT_EDGE : 0));
    soc::write(regs::SPI_USER1, 0);
    soc::write(regs::SPI_USER2, 0);
    soc::write(regs::SPI_MISC, regs::SPI_MISC_CS_ALL_DISABLED | (cpol ? regs::SPI_MISC_CK_IDLE_EDGE : 0));
    uint order = config.bit_order == BitOrder.LSB_FIRST ? regs::SPI_CTRL_WR_BIT_ORDER | regs::SPI_CTRL_RD_BIT_ORDER : 0;
    soc::modify(regs::SPI_CTRL, regs::SPI_CTRL_WR_BIT_ORDER | regs::SPI_CTRL_RD_BIT_ORDER, order);
    soc::write(regs::SPI_CLOCK, clock);
    apply_config();

    bus_sck = sck;
    bus_mosi = mosi;
    soc::route_output(sck, regs::SIG_FSPICLK);
    soc::route_output(mosi, regs::SIG_FSPID);
    soc::route_input(regs::SIG_FSPIQ, miso);
    return { actual };
}

fn void Bus.close(self) {
    soc::disable_peripheral(regs::PERIP_SPI2);
    soc::release_pin(bus_sck);
    soc::release_pin(bus_mosi);
}

fn uint Bus.frequency(self) => self.frequency_hz;

// One hardware transaction of up to 64 bytes. `tx` empty sends `fill`;
// `rx` empty drops the received bytes.
fn void chunk(char[] tx, char[] rx, usz len, char fill) @local {
    for (usz word = 0; word < (len + 3) / 4; word++) {
        uint value = 0;
        for (usz b = 0; b < 4; b++) {
            usz i = word * 4 + b;
            char byte = i < len ? (tx.len > 0 ? tx[i] : fill) : fill;
            value |= (uint)byte << (8 * b);
        }
        soc::write(regs::SPI_W0 + (uint)word * 4, value);
    }
    soc::write(regs::SPI_MS_DLEN, (uint)len * 8 - 1);
    apply_config();
    soc::write(regs::SPI_DMA_INT_CLR, regs::SPI_INT_TRANS_DONE);
    soc::write(regs::SPI_CMD, regs::SPI_CMD_USR);
    while ((soc::read(regs::SPI_DMA_INT_RAW) & regs::SPI_INT_TRANS_DONE) == 0) {}
    if (rx.len == 0) return;
    for (usz i = 0; i < len; i++) {
        uint value = soc::read(regs::SPI_W0 + (uint)(i / 4) * 4);
        rx[i] = (char)(value >> (8 * (i % 4)));
    }
}

fn void run(char[] tx, char[] rx, char fill) @local {
    usz len = tx.len > 0 ? tx.len : rx.len;
    for (usz done = 0; done < len; done += BUFFER_BYTES) {
        usz n = len - done < BUFFER_BYTES ? len - done : BUFFER_BYTES;
        chunk(tx.len > 0 ? tx[done:n] : tx, rx.len > 0 ? rx[done:n] : rx, n, fill);
    }
}

fn char Bus.transfer_byte(self, char byte) {
    char[1] tx = { byte };
    char[1] rx;
    run(&tx, &rx, 0xFF);
    return rx[0];
}

fn void? Bus.transfer(self, char[] tx, char[] rx) {
    if (tx.len > 0 && rx.len > 0 && tx.len != rx.len) return INVALID_LENGTH~;
    run(tx, rx, 0xFF);
}

fn void Bus.write(self, char[] data) => run(data, {}, 0xFF);
fn void Bus.read(self, char[] buffer, char fill = 0xFF) => run({}, buffer, fill);
