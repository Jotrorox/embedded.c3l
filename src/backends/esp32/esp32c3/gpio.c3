module embedded::gpio;

const uint GPIO_BASE = 0x6000_4000;
const uint IO_MUX_BASE = 0x6000_9000;
const uint TIMG0_BASE = 0x6001_F000;

const uint GPIO_OUT_REG = GPIO_BASE + 0x004;
const uint GPIO_OUT_W1TS = GPIO_BASE + 0x008;
const uint GPIO_OUT_W1TC = GPIO_BASE + 0x00C;
const uint GPIO_ENABLE_W1TS = GPIO_BASE + 0x024;
const uint GPIO_ENABLE_W1TC = GPIO_BASE + 0x028;
const uint GPIO_IN_REG = GPIO_BASE + 0x03C;

const uint GPIO_FUNC_OUT_SEL_BASE = GPIO_BASE + 0x554;
const uint GPIO_FUNC_OUT_SEL_STRIDE = 4;

const uint IO_MUX_GPIO_BASE = IO_MUX_BASE + 0x004;
const uint IO_MUX_GPIO_STRIDE = 4;

const uint IO_MUX_INPUT_VALUE = (1u << 12) | (1u << 9);
const uint IO_MUX_INPUT_PULLUP_VALUE = (1u << 12) | (1u << 9) | (1u << 8);
const uint IO_MUX_INPUT_PULLDOWN_VALUE = (1u << 12) | (1u << 9) | (1u << 7);

const uint IO_MUX_OUTPUT_VALUE = (2u << 10) | (1u << 12);
const uint GPIO_FUNC_OUTPUT_VALUE = 0x80u | (1u << 9);

const uint TIMG_WDTFEED_OFFSET = 0x0060;

fn void reg_write(uint addr, uint value) {
    @volatile_store(*(uint*)addr, value);
}

fn uint reg_read(uint addr) {
    return @volatile_load(*(uint*)addr);
}

fn void feed_mwdt() {
    reg_write(TIMG0_BASE + TIMG_WDTFEED_OFFSET, 1);
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
    return IO_MUX_GPIO_BASE + (uint)pin * IO_MUX_GPIO_STRIDE;
}

fn uint pin_out_sel_reg(Pin pin) {
    return GPIO_FUNC_OUT_SEL_BASE + (uint)pin * GPIO_FUNC_OUT_SEL_STRIDE;
}

fn void? configure(Pin pin, Config config) {
    if (!is_valid(pin)) return INVALID_PIN~;
    feed_mwdt();
    if (config.direction == Direction.INPUT_OUTPUT || config.direction == Direction.DISABLED) return UNSUPPORTED_MODE~;
    if (config.pull == Pull.UP_DOWN) return UNSUPPORTED_PULL~;
    if (config.output_type == OutputType.OPEN_DRAIN) return UNSUPPORTED_DRIVE~;
    if (config.drive_strength != DriveStrength.DEFAULT) return UNSUPPORTED_DRIVE~;

    switch (config.direction) {
        case Direction.OUTPUT:
            if (config.pull != Pull.NONE) return UNSUPPORTED_PULL~;
            if (config.initial_state == PinState.HIGH) {
                reg_write(GPIO_OUT_W1TS, pin_mask(pin));
            } else {
                reg_write(GPIO_OUT_W1TC, pin_mask(pin));
            }
            reg_write(pin_io_mux_reg(pin), IO_MUX_OUTPUT_VALUE);
            reg_write(pin_out_sel_reg(pin), GPIO_FUNC_OUTPUT_VALUE);
            reg_write(GPIO_ENABLE_W1TS, pin_mask(pin));
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
            reg_write(GPIO_ENABLE_W1TC, pin_mask(pin));
        default:
            return UNSUPPORTED_MODE~;
    }
}

fn void? write(Pin pin, PinState state) {
    if (!is_valid(pin)) return INVALID_PIN~;
    feed_mwdt();
    if (state == PinState.HIGH) {
        reg_write(GPIO_OUT_W1TS, pin_mask(pin));
    } else {
        reg_write(GPIO_OUT_W1TC, pin_mask(pin));
    }
}

fn PinState? read(Pin pin) {
    if (!is_valid(pin)) return INVALID_PIN~;
    feed_mwdt();
    return (reg_read(GPIO_IN_REG) & pin_mask(pin)) != 0 ? PinState.HIGH : PinState.LOW;
}

fn void? toggle(Pin pin) {
    PinState state = read_output(pin)!!;
    write(pin, state == PinState.HIGH ? PinState.LOW : PinState.HIGH)!!;
}

fn PinState? read_output(Pin pin) {
    if (!is_valid(pin)) return INVALID_PIN~;
    feed_mwdt();
    return (reg_read(GPIO_OUT_REG) & pin_mask(pin)) != 0 ? PinState.HIGH : PinState.LOW;
}

fn void? reset(Pin pin) {
    if (!is_valid(pin)) return INVALID_PIN~;
    feed_mwdt();
    reg_write(GPIO_OUT_W1TC, pin_mask(pin));
    reg_write(pin_io_mux_reg(pin), IO_MUX_INPUT_VALUE);
    reg_write(GPIO_ENABLE_W1TC, pin_mask(pin));
}
