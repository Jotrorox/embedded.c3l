module embedded::backends::esp32::esp32c3::soc;

import embedded::gpio;
import embedded::backends::esp32::esp32c3::regs;

// Shared ESP32-C3 helpers for the backend modules: register access,
// peripheral clock gating, clock frequencies and GPIO-matrix routing. Not
// part of the public API. Register addresses and fields are in regs.c3.

const uint XTAL_HZ = 40_000_000;
const uint RC_FAST_HZ = 17_500_000;

macro uint read(uint addr) => @volatile_load(*(uint*)addr);
macro void write(uint addr, uint value) => @volatile_store(*(uint*)addr, value);
macro void set_bits(uint addr, uint mask) => write(addr, read(addr) | mask);
macro void clear_bits(uint addr, uint mask) => write(addr, read(addr) & ~mask);

// Replaces the bits in `mask` with `value` (already shifted into place).
macro void modify(uint addr, uint mask, uint value) => write(addr, (read(addr) & ~mask) | (value & mask));

// Turns a peripheral's bus clock on and pulses its reset, leaving it in its
// power-on state. `mask` is one of the regs::PERIP_* bits.
fn void enable_peripheral(uint mask) {
    set_bits(regs::SYSTEM_PERIP_CLK_EN0, mask);
    set_bits(regs::SYSTEM_PERIP_RST_EN0, mask);
    clear_bits(regs::SYSTEM_PERIP_RST_EN0, mask);
}

fn void disable_peripheral(uint mask) {
    set_bits(regs::SYSTEM_PERIP_RST_EN0, mask);
    clear_bits(regs::SYSTEM_PERIP_CLK_EN0, mask);
}

// The APB clock, derived from whatever clock tree the boot ROM left. The
// library does not reprogram the clocks, so peripherals that can run from the
// 40 MHz crystal (UART, LEDC, I2C, SPI) use it directly and only the SAR ADC
// depends on this.
fn uint apb_hz() {
    uint conf = read(regs::SYSTEM_SYSCLK_CONF);
    uint divider = (conf & regs::SYSTEM_PRE_DIV_CNT_MASK) + 1;
    switch ((conf & regs::SYSTEM_SOC_CLK_SEL_MASK) >> regs::SYSTEM_SOC_CLK_SEL_SHIFT) {
        case regs::SYSTEM_SOC_CLK_SEL_XTAL: return XTAL_HZ / divider;
        case regs::SYSTEM_SOC_CLK_SEL_PLL: return 80_000_000;
        default: return RC_FAST_HZ / divider;
    }
}

fn uint io_mux_reg(gpio::Pin pin) => regs::IO_MUX_GPIO0 + (uint)pin * 4;
fn uint pin_reg(gpio::Pin pin) => regs::GPIO_PIN0 + (uint)pin * 4;

// Connects peripheral output `signal` (gpio_sig_map.h) to `pin` and enables
// the pad driver. Open drain is for buses such as I2C; the pad's input stays
// enabled so the peripheral can read the line back.
fn void route_output(gpio::Pin pin, uint signal, bool open_drain = false, bool pull_up = false) {
    uint mux = regs::IO_MUX_MCU_SEL_GPIO | regs::IO_MUX_FUN_DRV_DEFAULT | regs::IO_MUX_FUN_IE;
    if (pull_up) mux |= regs::IO_MUX_FUN_WPU;
    write(io_mux_reg(pin), mux);
    if (open_drain) {
        set_bits(pin_reg(pin), regs::GPIO_PIN_PAD_DRIVER);
    } else {
        clear_bits(pin_reg(pin), regs::GPIO_PIN_PAD_DRIVER);
    }
    write(regs::GPIO_FUNC0_OUT_SEL_CFG + (uint)pin * 4, signal | regs::GPIO_FUNC_OUT_OEN_SEL);
    write(regs::GPIO_ENABLE_W1TS, 1u << (uint)pin);
}

// Connects `pin` to peripheral input `signal` through the GPIO matrix.
fn void route_input(uint signal, gpio::Pin pin, bool pull_up = false) {
    uint mux = regs::IO_MUX_MCU_SEL_GPIO | regs::IO_MUX_FUN_DRV_DEFAULT | regs::IO_MUX_FUN_IE;
    if (pull_up) mux |= regs::IO_MUX_FUN_WPU;
    write(io_mux_reg(pin), mux);
    write(regs::GPIO_FUNC0_IN_SEL_CFG + signal * 4, (uint)pin | regs::GPIO_FUNC_IN_SEL_ROUTE);
}

// Returns a pin to a plain floating input driven by GPIO_OUT, undoing
// `route_output()`.
fn void release_pin(gpio::Pin pin) {
    write(regs::GPIO_ENABLE_W1TC, 1u << (uint)pin);
    write(regs::GPIO_FUNC0_OUT_SEL_CFG + (uint)pin * 4, regs::GPIO_OUT_SIGNAL_SIMPLE);
    clear_bits(pin_reg(pin), regs::GPIO_PIN_PAD_DRIVER);
    write(io_mux_reg(pin), regs::IO_MUX_MCU_SEL_GPIO | regs::IO_MUX_FUN_DRV_DEFAULT | regs::IO_MUX_FUN_IE);
}

// Disconnects the pad from every digital function for analog use (ADC).
fn void make_analog(gpio::Pin pin) {
    write(regs::GPIO_ENABLE_W1TC, 1u << (uint)pin);
    write(regs::GPIO_FUNC0_OUT_SEL_CFG + (uint)pin * 4, regs::GPIO_OUT_SIGNAL_SIMPLE);
    write(io_mux_reg(pin), regs::IO_MUX_MCU_SEL_GPIO | regs::IO_MUX_FUN_DRV_DEFAULT);
}
