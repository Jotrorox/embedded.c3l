module embedded::backends::esp32::esp32c3::soc;

import embedded::gpio;

// Shared ESP32-C3 definitions for the backend modules: register access,
// peripheral clock gating, clock frequencies and GPIO-matrix routing. Not
// part of the public API. Addresses and fields follow the ESP32-C3 TRM and
// ESP-IDF v5.3 (components/soc/esp32c3/include/soc).

const uint XTAL_HZ = 40_000_000;
const uint RC_FAST_HZ = 17_500_000;

// SYSTEM (clock and reset control).
const uint SYSTEM_BASE = 0x600C_0000;
const uint SYSTEM_PERIP_CLK_EN0 = SYSTEM_BASE + 0x010;
const uint SYSTEM_PERIP_RST_EN0 = SYSTEM_BASE + 0x018;
const uint SYSTEM_SYSCLK_CONF   = SYSTEM_BASE + 0x058;

// Bits shared by SYSTEM_PERIP_CLK_EN0 and SYSTEM_PERIP_RST_EN0.
const uint PERIP_UART0      = 1u << 2;
const uint PERIP_UART1      = 1u << 5;
const uint PERIP_SPI2       = 1u << 6;
const uint PERIP_I2C_EXT0   = 1u << 7;
const uint PERIP_LEDC       = 1u << 11;
const uint PERIP_UART_MEM   = 1u << 24;
const uint PERIP_APB_SARADC = 1u << 28;
const uint PERIP_SYSTIMER   = 1u << 29;

// GPIO matrix and IO MUX.
const uint GPIO_BASE = 0x6000_4000;
const uint GPIO_ENABLE_W1TS = GPIO_BASE + 0x024;
const uint GPIO_ENABLE_W1TC = GPIO_BASE + 0x028;
const uint GPIO_PIN0 = GPIO_BASE + 0x074;
const uint GPIO_FUNC0_IN_SEL_CFG = GPIO_BASE + 0x154;
const uint GPIO_FUNC0_OUT_SEL_CFG = GPIO_BASE + 0x554;
const uint IO_MUX_GPIO0 = 0x6000_9000 + 0x004;

const uint GPIO_PIN_PAD_DRIVER = 1u << 2;     // open drain
const uint GPIO_FUNC_IN_SEL_ROUTE = 1u << 6;  // take the signal from the matrix
const uint GPIO_FUNC_OUT_OEN_SEL = 1u << 9;   // output enable from GPIO_ENABLE
const uint GPIO_OUT_SIGNAL_SIMPLE = 0x80;     // plain GPIO_OUT bit
const uint IO_MUX_FUN_WPD = 1u << 7;
const uint IO_MUX_FUN_WPU = 1u << 8;
const uint IO_MUX_FUN_IE  = 1u << 9;
const uint IO_MUX_FUN_DRV_DEFAULT = 2u << 10; // ~20 mA
const uint IO_MUX_MCU_SEL_GPIO = 1u << 12;    // function 1: GPIO / matrix

macro uint read(uint addr) => @volatile_load(*(uint*)addr);
macro void write(uint addr, uint value) => @volatile_store(*(uint*)addr, value);
macro void set_bits(uint addr, uint mask) => write(addr, read(addr) | mask);
macro void clear_bits(uint addr, uint mask) => write(addr, read(addr) & ~mask);

// Replaces the bits in `mask` with `value` (already shifted into place).
macro void modify(uint addr, uint mask, uint value) => write(addr, (read(addr) & ~mask) | (value & mask));

// Turns a peripheral's bus clock on and pulses its reset, leaving it in its
// power-on state. `mask` is one of the PERIP_* bits.
fn void enable_peripheral(uint mask) {
    set_bits(SYSTEM_PERIP_CLK_EN0, mask);
    set_bits(SYSTEM_PERIP_RST_EN0, mask);
    clear_bits(SYSTEM_PERIP_RST_EN0, mask);
}

fn void disable_peripheral(uint mask) {
    set_bits(SYSTEM_PERIP_RST_EN0, mask);
    clear_bits(SYSTEM_PERIP_CLK_EN0, mask);
}

// The APB clock, derived from whatever clock tree the boot ROM left. The
// library does not reprogram the clocks, so peripherals that can run from the
// 40 MHz crystal (UART, LEDC, I2C, SPI) use it directly and only the SAR ADC
// depends on this.
fn uint apb_hz() {
    uint conf = read(SYSTEM_SYSCLK_CONF);
    uint divider = (conf & 0x3FF) + 1;
    switch ((conf >> 10) & 0x3) {
        case 0: return XTAL_HZ / divider;
        case 1: return 80_000_000;
        default: return RC_FAST_HZ / divider;
    }
}

fn uint io_mux_reg(gpio::Pin pin) => IO_MUX_GPIO0 + (uint)pin * 4;
fn uint pin_reg(gpio::Pin pin) => GPIO_PIN0 + (uint)pin * 4;

// Connects peripheral output `signal` (gpio_sig_map.h) to `pin` and enables
// the pad driver. Open drain is for buses such as I2C; the pad's input stays
// enabled so the peripheral can read the line back.
fn void route_output(gpio::Pin pin, uint signal, bool open_drain = false, bool pull_up = false) {
    uint mux = IO_MUX_MCU_SEL_GPIO | IO_MUX_FUN_DRV_DEFAULT | IO_MUX_FUN_IE;
    if (pull_up) mux |= IO_MUX_FUN_WPU;
    write(io_mux_reg(pin), mux);
    if (open_drain) {
        set_bits(pin_reg(pin), GPIO_PIN_PAD_DRIVER);
    } else {
        clear_bits(pin_reg(pin), GPIO_PIN_PAD_DRIVER);
    }
    write(GPIO_FUNC0_OUT_SEL_CFG + (uint)pin * 4, signal | GPIO_FUNC_OUT_OEN_SEL);
    write(GPIO_ENABLE_W1TS, 1u << (uint)pin);
}

// Connects `pin` to peripheral input `signal` through the GPIO matrix.
fn void route_input(uint signal, gpio::Pin pin, bool pull_up = false) {
    uint mux = IO_MUX_MCU_SEL_GPIO | IO_MUX_FUN_DRV_DEFAULT | IO_MUX_FUN_IE;
    if (pull_up) mux |= IO_MUX_FUN_WPU;
    write(io_mux_reg(pin), mux);
    write(GPIO_FUNC0_IN_SEL_CFG + signal * 4, (uint)pin | GPIO_FUNC_IN_SEL_ROUTE);
}

// Returns a pin to a plain floating input driven by GPIO_OUT, undoing
// `route_output()`.
fn void release_pin(gpio::Pin pin) {
    write(GPIO_ENABLE_W1TC, 1u << (uint)pin);
    write(GPIO_FUNC0_OUT_SEL_CFG + (uint)pin * 4, GPIO_OUT_SIGNAL_SIMPLE);
    clear_bits(pin_reg(pin), GPIO_PIN_PAD_DRIVER);
    write(io_mux_reg(pin), IO_MUX_MCU_SEL_GPIO | IO_MUX_FUN_DRV_DEFAULT | IO_MUX_FUN_IE);
}

// Disconnects the pad from every digital function for analog use (ADC).
fn void make_analog(gpio::Pin pin) {
    write(GPIO_ENABLE_W1TC, 1u << (uint)pin);
    write(GPIO_FUNC0_OUT_SEL_CFG + (uint)pin * 4, GPIO_OUT_SIGNAL_SIMPLE);
    write(io_mux_reg(pin), IO_MUX_MCU_SEL_GPIO | IO_MUX_FUN_DRV_DEFAULT);
}
