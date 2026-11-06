module embedded::spi;

import embedded::gpio;
import embedded::board;
import embedded::backends::esp32::esp32c3::soc;

// GP-SPI2 as a CPU-driven full-duplex master: up to 64 bytes per hardware
// transaction through the W0..W15 data buffer. Configuration registers are
// copied into the SPI clock domain by CMD.UPDATE. Follows ESP-IDF v5.3's
// spi_ll for the ESP32-C3.
const uint SPI_BASE = 0x6002_4000;
const uint CMD      = SPI_BASE + 0x00;
const uint CTRL     = SPI_BASE + 0x08;
const uint CLOCK    = SPI_BASE + 0x0C;
const uint USER     = SPI_BASE + 0x10;
const uint USER1    = SPI_BASE + 0x14;
const uint USER2    = SPI_BASE + 0x18;
const uint MS_DLEN  = SPI_BASE + 0x1C;
const uint MISC     = SPI_BASE + 0x20;
const uint DMA_CONF = SPI_BASE + 0x30;
const uint DMA_INT_CLR = SPI_BASE + 0x38;
const uint DMA_INT_RAW = SPI_BASE + 0x3C;
const uint W0       = SPI_BASE + 0x98;
const uint SLAVE    = SPI_BASE + 0xE0;
const uint CLK_GATE = SPI_BASE + 0xE8;

// CMD
const uint CMD_USR = 1u << 24;
const uint CMD_UPDATE = 1u << 23;
// CTRL
const uint CTRL_WR_BIT_ORDER = 1u << 26;
const uint CTRL_RD_BIT_ORDER = 1u << 25;
// CLOCK
const uint CLOCK_EQU_SYSCLK = 1u << 31;
// USER
const uint USER_USR_MISO = 1u << 28;
const uint USER_USR_MOSI = 1u << 27;
const uint USER_CK_OUT_EDGE = 1u << 9;
const uint USER_DOUTDIN = 1u << 0;
// MISC: CK_IDLE_EDGE is CPOL; all six hardware CS lines disabled.
const uint MISC_CK_IDLE_EDGE = 1u << 29;
const uint MISC_CS_ALL_DISABLED = 0x3F;
// DMA_INT_RAW / CLR
const uint INT_TRANS_DONE = 1u << 12;
// CLK_GATE: clock on, master clock on, master clock from XTAL (MST_CLK_SEL 0).
const uint CLK_GATE_VALUE = (1u << 1) | (1u << 0);

const uint BUFFER_BYTES = 64;
const uint SIGNAL_CLK  = 63; // FSPICLK_OUT_IDX
const uint SIGNAL_MISO = 64; // FSPIQ_IN_IDX
const uint SIGNAL_MOSI = 65; // FSPID_OUT_IDX

struct Bus {
    uint frequency_hz;
}

gpio::Pin bus_sck @local;
gpio::Pin bus_mosi @local;

fn Bus? open(Config config = {}) => open_pins(board::SPI_SCK, board::SPI_MOSI, board::SPI_MISO, config);

// Finds the highest clock 40 MHz / (pre * n), pre 1..16, n 2..64, not above
// `hz`, and returns the CLOCK register value (0 if none fits).
fn uint clock_register(uint hz, uint* actual) @local {
    if (hz >= soc::XTAL_HZ) {
        *actual = soc::XTAL_HZ;
        return CLOCK_EQU_SYSCLK;
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
    return ((best_pre - 1) << 18) | ((best_n - 1) << 12) | ((high - 1) << 6) | (best_n - 1);
}

fn void apply_config() @local {
    soc::write(CMD, CMD_UPDATE);
    while ((soc::read(CMD) & CMD_UPDATE) != 0) {}
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

    soc::enable_peripheral(soc::PERIP_SPI2);
    soc::write(CLK_GATE, CLK_GATE_VALUE);
    soc::write(SLAVE, 0);
    soc::write(DMA_CONF, 0);
    soc::write(USER, USER_DOUTDIN | USER_USR_MOSI | USER_USR_MISO | (out_edge ? USER_CK_OUT_EDGE : 0));
    soc::write(USER1, 0);
    soc::write(USER2, 0);
    soc::write(MISC, MISC_CS_ALL_DISABLED | (cpol ? MISC_CK_IDLE_EDGE : 0));
    uint order = config.bit_order == BitOrder.LSB_FIRST ? CTRL_WR_BIT_ORDER | CTRL_RD_BIT_ORDER : 0;
    soc::modify(CTRL, CTRL_WR_BIT_ORDER | CTRL_RD_BIT_ORDER, order);
    soc::write(CLOCK, clock);
    apply_config();

    bus_sck = sck;
    bus_mosi = mosi;
    soc::route_output(sck, SIGNAL_CLK);
    soc::route_output(mosi, SIGNAL_MOSI);
    soc::route_input(SIGNAL_MISO, miso);
    return { actual };
}

fn void Bus.close(self) {
    soc::disable_peripheral(soc::PERIP_SPI2);
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
        soc::write(W0 + (uint)word * 4, value);
    }
    soc::write(MS_DLEN, (uint)len * 8 - 1);
    apply_config();
    soc::write(DMA_INT_CLR, INT_TRANS_DONE);
    soc::write(CMD, CMD_USR);
    while ((soc::read(DMA_INT_RAW) & INT_TRANS_DONE) == 0) {}
    if (rx.len == 0) return;
    for (usz i = 0; i < len; i++) {
        uint value = soc::read(W0 + (uint)(i / 4) * 4);
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
