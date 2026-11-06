module embedded::uart;

import embedded::gpio;
import embedded::time;
import embedded::backends::esp32::esp32c3::soc;

constdef Port : inline char {
    UART0 = 0,
    UART1 = 1,
    USB_SERIAL_JTAG = 2,
}

// UART0/UART1 register block (offsets from the port base).
const uint UART0_BASE = 0x6000_0000;
const uint UART1_BASE = 0x6001_0000;
const uint FIFO      = 0x00;
const uint INT_RAW   = 0x04;
const uint INT_CLR   = 0x10;
const uint CLKDIV    = 0x14;
const uint STATUS    = 0x1C;
const uint CONF0     = 0x20;
const uint CONF1     = 0x24;
const uint FSM_STATUS = 0x6C;
const uint CLK_CONF  = 0x78;

// INT_RAW
const uint INT_PARITY_ERR = 1u << 2;
const uint INT_FRM_ERR    = 1u << 3;
const uint INT_RXFIFO_OVF = 1u << 4;
const uint INT_LINE_ERRORS = INT_PARITY_ERR | INT_FRM_ERR | INT_RXFIFO_OVF;
// STATUS
const uint STATUS_RXFIFO_CNT_MASK = 0x3FF;
const uint STATUS_TXFIFO_CNT_SHIFT = 16;
const uint STATUS_TXFIFO_CNT_MASK = 0x3FFu << 16;
// CONF0
const uint CONF0_TXFIFO_RST = 1u << 18;
const uint CONF0_RXFIFO_RST = 1u << 17;
const uint CONF0_STOP_BIT_SHIFT = 4;
const uint CONF0_BIT_NUM_SHIFT = 2;
const uint CONF0_PARITY_EN = 1u << 1;
const uint CONF0_PARITY_ODD = 1u << 0;
const uint CONF0_MEM_CLK_EN = 1u << 28;
// CLK_CONF
const uint CLK_CONF_RST_CORE = 1u << 23;
const uint CLK_CONF_SCLK_EN = 1u << 22;
const uint CLK_CONF_RX_SCLK_EN = 1u << 25;
const uint CLK_CONF_TX_SCLK_EN = 1u << 24;
const uint CLK_CONF_SCLK_SEL_XTAL = 3u << 20;
const uint CLK_CONF_SCLK_DIV_NUM_SHIFT = 12;
const uint CLK_CONF_SCLK_DIV_NUM_MASK = 0xFFu << 12;
// FSM_STATUS
const uint FSM_ST_UTX_OUT_MASK = 0xF0;

const uint TX_FIFO_SIZE = 128;
const uint MAX_CLKDIV_INT = 0xFFF;
const uint MAX_SCLK_DIV = 256;

// GPIO-matrix signals (gpio_sig_map.h); TX out and RX in share an index.
const uint U0_SIGNAL = 6;
const uint U1_SIGNAL = 9;

const gpio::Pin UART0_TX_PIN = (gpio::Pin)21;
const gpio::Pin UART0_RX_PIN = (gpio::Pin)20;
const gpio::Pin UART1_TX_PIN = (gpio::Pin)0;
const gpio::Pin UART1_RX_PIN = (gpio::Pin)1;

// USB-Serial-JTAG: a 64-byte FIFO in each direction behind one data register.
const uint USJ_BASE = 0x6004_3000;
const uint USJ_EP1 = USJ_BASE + 0x00;
const uint USJ_EP1_CONF = USJ_BASE + 0x04;
const uint USJ_WR_DONE = 1u << 0;
const uint USJ_IN_EP_DATA_FREE = 1u << 1;
const uint USJ_OUT_EP_DATA_AVAIL = 1u << 2;
const ulong USJ_STALL_TIMEOUT_US = 50_000;

const uint MAX_BAUD_ERROR_PERMILLE = 25;

struct Uart {
    Port port;
}

// Set once a USB write timed out because no host drained the FIFO. While set,
// writes drop bytes at once instead of waiting 50 ms each.
bool usj_stalled @local = false;
gpio::Pin[2] port_tx @local;
gpio::Pin[2] port_rx @local;

fn bool is_valid(Port port) => (uint)port <= (uint)Port.USB_SERIAL_JTAG;

fn uint base_of(Port port) @local => port == Port.UART1 ? UART1_BASE : UART0_BASE;
fn uint reg(Port port, uint offset) @local => base_of(port) + offset;

fn Uart? open(Port port, Config config = {}) {
    switch (port) {
        case Port.UART0: return open_pins(port, UART0_TX_PIN, UART0_RX_PIN, config);
        case Port.UART1: return open_pins(port, UART1_TX_PIN, UART1_RX_PIN, config);
        case Port.USB_SERIAL_JTAG: return { port };
        default: return INVALID_PORT~;
    }
}

fn Uart? open_pins(Port port, gpio::Pin tx, gpio::Pin rx, Config config = {}) {
    if (!is_valid(port)) return INVALID_PORT~;
    if (port == Port.USB_SERIAL_JTAG) {
        // Fixed to the USB pins; nothing to configure.
        if (tx != 19 || rx != 18) return INVALID_PINS~;
        return { port };
    }
    if (!gpio::is_valid(tx) || !gpio::is_valid(rx) || tx == rx) return INVALID_PINS~;
    if ((char)config.data_bits > 3) return UNSUPPORTED_FORMAT~;

    uint baud = config.baud == 0 ? DEFAULT_BAUD : config.baud;
    // The 12.4 fixed-point divider needs at least 16 source clocks per bit.
    if (baud > soc::XTAL_HZ / 16) return UNSUPPORTED_BAUD~;
    // Pre-divide the 40 MHz crystal so the integer part fits in 12 bits.
    uint sclk_div = (soc::XTAL_HZ + MAX_CLKDIV_INT * baud - 1) / (MAX_CLKDIV_INT * baud);
    if (sclk_div == 0) sclk_div = 1;
    if (sclk_div > MAX_SCLK_DIV) return UNSUPPORTED_BAUD~;
    uint clkdiv = (uint)(((ulong)soc::XTAL_HZ << 4) / ((ulong)baud * sclk_div));
    uint actual = (uint)(((ulong)soc::XTAL_HZ << 4) / ((ulong)clkdiv * sclk_div));
    uint diff = actual > baud ? actual - baud : baud - actual;
    if ((ulong)diff * 1000 / baud > MAX_BAUD_ERROR_PERMILLE) return UNSUPPORTED_BAUD~;

    uint conf0 = CONF0_MEM_CLK_EN
        | ((3 - (uint)config.data_bits) << CONF0_BIT_NUM_SHIFT)
        | ((config.stop_bits == StopBits.TWO ? 3u : 1u) << CONF0_STOP_BIT_SHIFT);
    switch (config.parity) {
        case Parity.NONE: break;
        case Parity.EVEN: conf0 |= CONF0_PARITY_EN;
        case Parity.ODD:  conf0 |= CONF0_PARITY_EN | CONF0_PARITY_ODD;
        default: return UNSUPPORTED_FORMAT~;
    }

    // ESP-IDF's order: hold the core in reset while the bus clock and the
    // peripheral reset are cycled, otherwise TX may glitch.
    uint periph = port == Port.UART1 ? soc::PERIP_UART1 : soc::PERIP_UART0;
    soc::set_bits(soc::SYSTEM_PERIP_CLK_EN0, periph | soc::PERIP_UART_MEM);
    soc::set_bits(reg(port, CLK_CONF), CLK_CONF_RST_CORE);
    soc::set_bits(soc::SYSTEM_PERIP_RST_EN0, periph);
    soc::clear_bits(soc::SYSTEM_PERIP_RST_EN0, periph);
    soc::clear_bits(reg(port, CLK_CONF), CLK_CONF_RST_CORE);

    soc::write(reg(port, CLK_CONF), CLK_CONF_SCLK_SEL_XTAL | CLK_CONF_SCLK_EN
        | CLK_CONF_RX_SCLK_EN | CLK_CONF_TX_SCLK_EN
        | ((sclk_div - 1) << CLK_CONF_SCLK_DIV_NUM_SHIFT));
    soc::write(reg(port, CLKDIV), ((clkdiv & 0xF) << 20) | (clkdiv >> 4));
    soc::write(reg(port, CONF0), conf0 | CONF0_TXFIFO_RST | CONF0_RXFIFO_RST);
    soc::write(reg(port, CONF0), conf0);
    soc::write(reg(port, INT_CLR), 0xFFFF_FFFF);

    uint signal = port == Port.UART1 ? U1_SIGNAL : U0_SIGNAL;
    soc::route_input(signal, rx, pull_up: true);
    soc::route_output(tx, signal);
    port_tx[(uint)port] = tx;
    port_rx[(uint)port] = rx;
    return { port };
}

fn void Uart.close(self) {
    self.flush();
    if (self.port == Port.USB_SERIAL_JTAG) return;
    soc::disable_peripheral(self.port == Port.UART1 ? soc::PERIP_UART1 : soc::PERIP_UART0);
    soc::release_pin(port_tx[(uint)self.port]);
    soc::release_pin(port_rx[(uint)self.port]);
}

fn uint Uart.baud(self) {
    if (self.port == Port.USB_SERIAL_JTAG) return 0;
    uint div = soc::read(reg(self.port, CLKDIV));
    uint clkdiv = ((div & MAX_CLKDIV_INT) << 4) | ((div >> 20) & 0xF);
    uint sclk_div = ((soc::read(reg(self.port, CLK_CONF)) & CLK_CONF_SCLK_DIV_NUM_MASK) >> CLK_CONF_SCLK_DIV_NUM_SHIFT) + 1;
    if (clkdiv == 0) return 0;
    return (uint)(((ulong)soc::XTAL_HZ << 4) / ((ulong)clkdiv * sclk_div));
}

// Waits up to 50 ms for room in the USB FIFO. Returns false (and remembers
// the stall) when no host is reading.
fn bool usj_wait_free() @local {
    if (soc::read(USJ_EP1_CONF) & USJ_IN_EP_DATA_FREE) {
        usj_stalled = false;
        return true;
    }
    if (usj_stalled) return false;
    soc::write(USJ_EP1_CONF, USJ_WR_DONE);
    time::Instant deadline = time::deadline_after(time::us(USJ_STALL_TIMEOUT_US));
    while (!time::has_elapsed(deadline)) {
        if (soc::read(USJ_EP1_CONF) & USJ_IN_EP_DATA_FREE) return true;
    }
    usj_stalled = true;
    return false;
}

fn void Uart.write_byte(self, char byte) {
    if (self.port == Port.USB_SERIAL_JTAG) {
        if (!usj_wait_free()) return;
        soc::write(USJ_EP1, byte);
        soc::write(USJ_EP1_CONF, USJ_WR_DONE);
        return;
    }
    uint status = reg(self.port, STATUS);
    while ((soc::read(status) & STATUS_TXFIFO_CNT_MASK) >> STATUS_TXFIFO_CNT_SHIFT >= TX_FIFO_SIZE) {}
    soc::write(reg(self.port, FIFO), byte);
}

fn void Uart.write(self, char[] bytes) {
    if (self.port != Port.USB_SERIAL_JTAG) {
        foreach (byte : bytes) self.write_byte(byte);
        return;
    }
    // One USB packet per FIFO load instead of one per byte.
    foreach (byte : bytes) {
        if (!usj_wait_free()) return;
        soc::write(USJ_EP1, byte);
    }
    soc::write(USJ_EP1_CONF, USJ_WR_DONE);
}

fn void Uart.flush(self) {
    if (self.port == Port.USB_SERIAL_JTAG) {
        soc::write(USJ_EP1_CONF, USJ_WR_DONE);
        return;
    }
    while ((soc::read(reg(self.port, STATUS)) & STATUS_TXFIFO_CNT_MASK) != 0) {}
    while ((soc::read(reg(self.port, FSM_STATUS)) & FSM_ST_UTX_OUT_MASK) != 0) {}
}

fn bool Uart.can_read(self) {
    if (self.port == Port.USB_SERIAL_JTAG) return (soc::read(USJ_EP1_CONF) & USJ_OUT_EP_DATA_AVAIL) != 0;
    return (soc::read(reg(self.port, STATUS)) & STATUS_RXFIFO_CNT_MASK) != 0;
}

fn char? Uart.try_read(self) {
    if (self.port == Port.USB_SERIAL_JTAG) {
        if ((soc::read(USJ_EP1_CONF) & USJ_OUT_EP_DATA_AVAIL) == 0) return NO_DATA~;
        return (char)soc::read(USJ_EP1);
    }
    if ((soc::read(reg(self.port, STATUS)) & STATUS_RXFIFO_CNT_MASK) == 0) return NO_DATA~;
    char byte = (char)soc::read(reg(self.port, FIFO));
    // The error flags are sticky interrupt bits rather than per byte, so an
    // error is reported once, with the next byte read after it happened.
    uint errors = soc::read(reg(self.port, INT_RAW)) & INT_LINE_ERRORS;
    if (errors != 0) {
        soc::write(reg(self.port, INT_CLR), errors);
        if (errors & INT_RXFIFO_OVF) return OVERRUN~;
        if (errors & INT_FRM_ERR) return FRAMING_ERROR~;
        return PARITY_ERROR~;
    }
    return byte;
}
