module embedded::uart @feat(MCU_ESP32C3);

import embedded::gpio;
import embedded::time;
import embedded::backends::esp32::esp32c3::soc;
import embedded::backends::esp32::esp32c3::regs;

constdef Port : inline char {
    UART0 = 0,
    UART1 = 1,
    USB_SERIAL_JTAG = 2,
}

const uint INT_LINE_ERRORS = regs::UART_INT_PARITY_ERR | regs::UART_INT_FRM_ERR | regs::UART_INT_RXFIFO_OVF;

const uint TX_FIFO_SIZE = 128;
const uint MAX_CLKDIV_INT = regs::UART_CLKDIV_INT_MASK;
const uint MAX_SCLK_DIV = 256;

const gpio::Pin UART0_TX_PIN = (gpio::Pin)21;
const gpio::Pin UART0_RX_PIN = (gpio::Pin)20;
const gpio::Pin UART1_TX_PIN = (gpio::Pin)0;
const gpio::Pin UART1_RX_PIN = (gpio::Pin)1;

// USB-Serial-JTAG writes give up after this long without a reading host.
const ulong USJ_STALL_TIMEOUT_US = 50_000;

const uint MAX_BAUD_ERROR_PERMILLE = 25;

struct Uart {
    Port port;
}

// Set once a USB write timed out because no host drained the regs::UART_FIFO. While set,
// writes drop bytes at once instead of waiting 50 ms each.
bool usj_stalled @local = false;
gpio::Pin[2] port_tx @local;
gpio::Pin[2] port_rx @local;

fn bool is_valid(Port port) => (uint)port <= (uint)Port.USB_SERIAL_JTAG;

fn uint base_of(Port port) @local => port == Port.UART1 ? regs::UART1_BASE : regs::UART0_BASE;
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

    uint conf0 = regs::UART_CONF0_MEM_CLK_EN
        | ((3 - (uint)config.data_bits) << regs::UART_CONF0_BIT_NUM_SHIFT)
        | ((config.stop_bits == StopBits.TWO ? 3u : 1u) << regs::UART_CONF0_STOP_BIT_NUM_SHIFT);
    switch (config.parity) {
        case Parity.NONE: break;
        case Parity.EVEN: conf0 |= regs::UART_CONF0_PARITY_EN;
        case Parity.ODD:  conf0 |= regs::UART_CONF0_PARITY_EN | regs::UART_CONF0_PARITY_ODD;
        default: return UNSUPPORTED_FORMAT~;
    }

    // ESP-IDF's order: hold the core in reset while the bus clock and the
    // peripheral reset are cycled, otherwise TX may glitch.
    uint periph = port == Port.UART1 ? regs::PERIP_UART1 : regs::PERIP_UART0;
    soc::set_bits(regs::SYSTEM_PERIP_CLK_EN0, periph | regs::PERIP_UART_MEM);
    soc::set_bits(reg(port, regs::UART_CLK_CONF), regs::UART_CLK_CONF_RST_CORE);
    soc::set_bits(regs::SYSTEM_PERIP_RST_EN0, periph);
    soc::clear_bits(regs::SYSTEM_PERIP_RST_EN0, periph);
    soc::clear_bits(reg(port, regs::UART_CLK_CONF), regs::UART_CLK_CONF_RST_CORE);

    soc::write(reg(port, regs::UART_CLK_CONF), regs::UART_CLK_CONF_SCLK_SEL_XTAL | regs::UART_CLK_CONF_SCLK_EN
        | regs::UART_CLK_CONF_RX_SCLK_EN | regs::UART_CLK_CONF_TX_SCLK_EN
        | ((sclk_div - 1) << regs::UART_CLK_CONF_SCLK_DIV_NUM_SHIFT));
    soc::write(reg(port, regs::UART_CLKDIV), ((clkdiv & 0xF) << regs::UART_CLKDIV_FRAG_SHIFT) | (clkdiv >> 4));
    soc::write(reg(port, regs::UART_CONF0), conf0 | regs::UART_CONF0_TXFIFO_RST | regs::UART_CONF0_RXFIFO_RST);
    soc::write(reg(port, regs::UART_CONF0), conf0);
    soc::write(reg(port, regs::UART_INT_CLR), 0xFFFF_FFFF);

    uint signal = port == Port.UART1 ? regs::SIG_U1 : regs::SIG_U0;
    soc::route_input(signal, rx, pull_up: true);
    soc::route_output(tx, signal);
    port_tx[(uint)port] = tx;
    port_rx[(uint)port] = rx;
    return { port };
}

fn void Uart.close(self) {
    self.flush();
    if (self.port == Port.USB_SERIAL_JTAG) return;
    soc::disable_peripheral(self.port == Port.UART1 ? regs::PERIP_UART1 : regs::PERIP_UART0);
    soc::release_pin(port_tx[(uint)self.port]);
    soc::release_pin(port_rx[(uint)self.port]);
}

fn uint Uart.baud(self) {
    if (self.port == Port.USB_SERIAL_JTAG) return 0;
    uint div = soc::read(reg(self.port, regs::UART_CLKDIV));
    uint clkdiv = ((div & regs::UART_CLKDIV_INT_MASK) << 4) | ((div & regs::UART_CLKDIV_FRAG_MASK) >> regs::UART_CLKDIV_FRAG_SHIFT);
    uint sclk_div = ((soc::read(reg(self.port, regs::UART_CLK_CONF)) & regs::UART_CLK_CONF_SCLK_DIV_NUM_MASK) >> regs::UART_CLK_CONF_SCLK_DIV_NUM_SHIFT) + 1;
    if (clkdiv == 0) return 0;
    return (uint)(((ulong)soc::XTAL_HZ << 4) / ((ulong)clkdiv * sclk_div));
}

// Waits up to 50 ms for room in the USB regs::UART_FIFO. Returns false (and remembers
// the stall) when no host is reading.
fn bool usj_wait_free() @local {
    if (soc::read(regs::USJ_EP1_CONF) & regs::USJ_IN_EP_DATA_FREE) {
        usj_stalled = false;
        return true;
    }
    if (usj_stalled) return false;
    soc::write(regs::USJ_EP1_CONF, regs::USJ_WR_DONE);
    time::Instant deadline = time::deadline_after(time::us(USJ_STALL_TIMEOUT_US));
    while (!time::has_elapsed(deadline)) {
        if (soc::read(regs::USJ_EP1_CONF) & regs::USJ_IN_EP_DATA_FREE) return true;
    }
    usj_stalled = true;
    return false;
}

fn void Uart.write_byte(self, char byte) {
    if (self.port == Port.USB_SERIAL_JTAG) {
        if (!usj_wait_free()) return;
        soc::write(regs::USJ_EP1, byte);
        soc::write(regs::USJ_EP1_CONF, regs::USJ_WR_DONE);
        return;
    }
    uint status = reg(self.port, regs::UART_STATUS);
    while ((soc::read(status) & regs::UART_STATUS_TXFIFO_CNT_MASK) >> regs::UART_STATUS_TXFIFO_CNT_SHIFT >= TX_FIFO_SIZE) {}
    soc::write(reg(self.port, regs::UART_FIFO), byte);
}

fn void Uart.write(self, char[] bytes) {
    if (self.port != Port.USB_SERIAL_JTAG) {
        foreach (byte : bytes) self.write_byte(byte);
        return;
    }
    // One USB packet per regs::UART_FIFO load instead of one per byte.
    foreach (byte : bytes) {
        if (!usj_wait_free()) return;
        soc::write(regs::USJ_EP1, byte);
    }
    soc::write(regs::USJ_EP1_CONF, regs::USJ_WR_DONE);
}

fn void Uart.flush(self) {
    if (self.port == Port.USB_SERIAL_JTAG) {
        soc::write(regs::USJ_EP1_CONF, regs::USJ_WR_DONE);
        return;
    }
    while ((soc::read(reg(self.port, regs::UART_STATUS)) & regs::UART_STATUS_TXFIFO_CNT_MASK) != 0) {}
    while ((soc::read(reg(self.port, regs::UART_FSM_STATUS)) & regs::UART_FSM_ST_UTX_OUT_MASK) != 0) {}
}

fn bool Uart.can_read(self) {
    if (self.port == Port.USB_SERIAL_JTAG) return (soc::read(regs::USJ_EP1_CONF) & regs::USJ_OUT_EP_DATA_AVAIL) != 0;
    return (soc::read(reg(self.port, regs::UART_STATUS)) & regs::UART_STATUS_RXFIFO_CNT_MASK) != 0;
}

fn char? Uart.try_read(self) {
    if (self.port == Port.USB_SERIAL_JTAG) {
        if ((soc::read(regs::USJ_EP1_CONF) & regs::USJ_OUT_EP_DATA_AVAIL) == 0) return NO_DATA~;
        return (char)soc::read(regs::USJ_EP1);
    }
    if ((soc::read(reg(self.port, regs::UART_STATUS)) & regs::UART_STATUS_RXFIFO_CNT_MASK) == 0) return NO_DATA~;
    char byte = (char)soc::read(reg(self.port, regs::UART_FIFO));
    // The error flags are sticky interrupt bits rather than per byte, so an
    // error is reported once, with the next byte read after it happened.
    uint errors = soc::read(reg(self.port, regs::UART_INT_RAW)) & INT_LINE_ERRORS;
    if (errors != 0) {
        soc::write(reg(self.port, regs::UART_INT_CLR), errors);
        if (errors & regs::UART_INT_RXFIFO_OVF) return OVERRUN~;
        if (errors & regs::UART_INT_FRM_ERR) return FRAMING_ERROR~;
        return PARITY_ERROR~;
    }
    return byte;
}
