module embedded::gpio @feat(MCU_ESP32C3);

import embedded::backends::esp32::esp32c3::regs;

const uint IO_MUX_INPUT_VALUE = regs::IO_MUX_MCU_SEL_GPIO | regs::IO_MUX_FUN_IE;
const uint IO_MUX_INPUT_PULLUP_VALUE = IO_MUX_INPUT_VALUE | regs::IO_MUX_FUN_WPU;
const uint IO_MUX_INPUT_PULLDOWN_VALUE = IO_MUX_INPUT_VALUE | regs::IO_MUX_FUN_WPD;

const uint IO_MUX_OUTPUT_VALUE = regs::IO_MUX_MCU_SEL_GPIO | regs::IO_MUX_FUN_DRV_DEFAULT;
const uint GPIO_FUNC_OUTPUT_VALUE = regs::GPIO_OUT_SIGNAL_SIMPLE | regs::GPIO_FUNC_OUT_OEN_SEL;

fn void reg_write(uint addr, uint value) {
    @volatile_store(*(uint*)(uptr)addr, value);
}

fn uint reg_read(uint addr) {
    return @volatile_load(*(uint*)(uptr)addr);
}

fn bool is_valid(Pin pin) {
    uint p = (uint)pin;
    return p <= 10 || (p >= 18 && p <= 21);
}

fn bool supports(Pin pin, Capability cap) {
    if (!is_valid(pin)) return false;
    switch (cap) {
        case Capability.INPUT:
        case Capability.OUTPUT:
        case Capability.PULL_UP:
        case Capability.PULL_DOWN:
            return true;
        default:
            return false;
    }
}

fn uint pin_mask(Pin pin) {
    return 1u << (uint)pin;
}

fn uint pin_io_mux_reg(Pin pin) {
    return regs::IO_MUX_GPIO0 + (uint)pin * 4;
}

fn uint pin_out_sel_reg(Pin pin) {
    return regs::GPIO_FUNC0_OUT_SEL_CFG + (uint)pin * 4;
}

fn void? configure(Pin pin, Config config) {
    if (!is_valid(pin)) return INVALID_PIN~;
    if (config.direction == Direction.INPUT_OUTPUT || config.direction == Direction.DISABLED) return UNSUPPORTED_MODE~;
    if (config.pull == Pull.UP_DOWN) return UNSUPPORTED_PULL~;
    if (config.output_type == OutputType.OPEN_DRAIN) return UNSUPPORTED_DRIVE~;
    if (config.drive_strength != DriveStrength.DEFAULT) return UNSUPPORTED_DRIVE~;

    switch (config.direction) {
        case Direction.OUTPUT:
            if (config.pull != Pull.NONE) return UNSUPPORTED_PULL~;
            if (config.initial_state == PinState.HIGH) {
                reg_write(regs::GPIO_OUT_W1TS, pin_mask(pin));
            } else {
                reg_write(regs::GPIO_OUT_W1TC, pin_mask(pin));
            }
            reg_write(pin_io_mux_reg(pin), IO_MUX_OUTPUT_VALUE);
            reg_write(pin_out_sel_reg(pin), GPIO_FUNC_OUTPUT_VALUE);
            reg_write(regs::GPIO_ENABLE_W1TS, pin_mask(pin));
        case Direction.INPUT:
            switch (config.pull) {
                case Pull.NONE:
                    reg_write(pin_io_mux_reg(pin), IO_MUX_INPUT_VALUE);
                case Pull.UP:
                    reg_write(pin_io_mux_reg(pin), IO_MUX_INPUT_PULLUP_VALUE);
                case Pull.DOWN:
                    reg_write(pin_io_mux_reg(pin), IO_MUX_INPUT_PULLDOWN_VALUE);
                default:
                    return UNSUPPORTED_PULL~;
            }
            reg_write(regs::GPIO_ENABLE_W1TC, pin_mask(pin));
        default:
            return UNSUPPORTED_MODE~;
    }
}

fn void? write(Pin pin, PinState state) {
    if (!is_valid(pin)) return INVALID_PIN~;
    if (state == PinState.HIGH) {
        reg_write(regs::GPIO_OUT_W1TS, pin_mask(pin));
    } else {
        reg_write(regs::GPIO_OUT_W1TC, pin_mask(pin));
    }
}

fn PinState? read(Pin pin) {
    if (!is_valid(pin)) return INVALID_PIN~;
    return (reg_read(regs::GPIO_IN) & pin_mask(pin)) != 0 ? PinState.HIGH : PinState.LOW;
}

fn void? toggle(Pin pin) {
    PinState state = read_output(pin)!;
    write(pin, state == PinState.HIGH ? PinState.LOW : PinState.HIGH)!;
}

fn PinState? read_output(Pin pin) {
    if (!is_valid(pin)) return INVALID_PIN~;
    return (reg_read(regs::GPIO_OUT) & pin_mask(pin)) != 0 ? PinState.HIGH : PinState.LOW;
}

fn void? reset(Pin pin) {
    if (!is_valid(pin)) return INVALID_PIN~;
    reg_write(regs::GPIO_OUT_W1TC, pin_mask(pin));
    reg_write(pin_io_mux_reg(pin), IO_MUX_INPUT_VALUE);
    reg_write(regs::GPIO_ENABLE_W1TC, pin_mask(pin));
}

// Handles. GPIO0..21 all live in the single 32-bit GPIO_OUT / GPIO_IN bank and
// have dedicated set/clear registers, so the bit mask is all a handle needs.
struct Output {
    uint mask;
}

struct Input {
    uint mask;
}

fn Output? output(Pin pin, PinState initial = PinState.LOW) @inline {
    configure(pin, { .direction = Direction.OUTPUT, .initial_state = initial })!;
    return { pin_mask(pin) };
}

fn Input? input(Pin pin, Pull pull = Pull.NONE) @inline {
    configure(pin, { .direction = Direction.INPUT, .pull = pull })!;
    return { pin_mask(pin) };
}

fn void Output.set(self) @inline {
    reg_write(regs::GPIO_OUT_W1TS, self.mask);
}

fn void Output.clear(self) @inline {
    reg_write(regs::GPIO_OUT_W1TC, self.mask);
}

fn void Output.toggle(self) @inline {
    reg_write((reg_read(regs::GPIO_OUT) & self.mask) != 0 ? regs::GPIO_OUT_W1TC : regs::GPIO_OUT_W1TS, self.mask);
}

fn void Output.write(self, PinState state) @inline {
    reg_write(state != PinState.LOW ? regs::GPIO_OUT_W1TS : regs::GPIO_OUT_W1TC, self.mask);
}

fn PinState Output.read(self) @inline {
    return (reg_read(regs::GPIO_OUT) & self.mask) != 0 ? PinState.HIGH : PinState.LOW;
}

fn PinState Input.read(self) @inline {
    return (reg_read(regs::GPIO_IN) & self.mask) != 0 ? PinState.HIGH : PinState.LOW;
}

fn bool Input.is_high(self) @inline => self.read() == PinState.HIGH;
fn bool Input.is_low(self) @inline => self.read() == PinState.LOW;
