module embedded::gpio @feat(MCU_ATMEGA328P);

import embedded::backends::avr::atmega328p::regs;

fn char get_port(Pin pin) {
    if ((int)pin <= 7) return (char)regs::PORTD;
    if ((int)pin <= 13) return (char)regs::PORTB;
    return (char)regs::PORTC;
}

fn char get_ddr(Pin pin) {
    if ((int)pin <= 7) return (char)regs::DDRD;
    if ((int)pin <= 13) return (char)regs::DDRB;
    return (char)regs::DDRC;
}

fn char get_pin_reg(Pin pin) {
    if ((int)pin <= 7) return (char)regs::PIND;
    if ((int)pin <= 13) return (char)regs::PINB;
    return (char)regs::PINC;
}

fn char get_bit(Pin pin) {
    if ((int)pin <= 7) return (char)pin;
    if ((int)pin <= 13) return (char)(pin - 8);
    return (char)((int)pin - 14);
}

fn void reg_set(char addr, char bit) {
    char* r = (char*)(uptr)addr;
    @volatile_store(*r, (char)(@volatile_load(*r) | (char)(1 << bit)));
}

fn void reg_clr(char addr, char bit) {
    char* r = (char*)(uptr)addr;
    @volatile_store(*r, (char)(@volatile_load(*r) & (char)~(1 << bit)));
}

fn void reg_clr_mask(char addr, char mask) {
    char* r = (char*)(uptr)addr;
    @volatile_store(*r, (char)(@volatile_load(*r) & (char)~mask));
}

fn char reg_read(char addr) {
    char* r = (char*)(uptr)addr;
    return @volatile_load(*r);
}

fn void disable_pwm(Pin pin) {
    switch (pin) {
        case (Pin)3:  reg_clr_mask((char)regs::TCCR2A, regs::COM_B_MASK); // OC2B
        case (Pin)5:  reg_clr_mask((char)regs::TCCR0A, regs::COM_B_MASK); // OC0B
        case (Pin)6:  reg_clr_mask((char)regs::TCCR0A, regs::COM_A_MASK); // OC0A
        case (Pin)9:  reg_clr_mask((char)regs::TCCR1A, regs::COM_A_MASK); // OC1A
        case (Pin)10: reg_clr_mask((char)regs::TCCR1A, regs::COM_B_MASK); // OC1B
        case (Pin)11: reg_clr_mask((char)regs::TCCR2A, regs::COM_A_MASK); // OC2A
        default:
    }
}

fn bool is_valid(Pin pin) {
    return (uint)pin < 20;
}

fn bool supports(Pin pin, Capability cap) {
    if (!is_valid(pin)) return false;
    switch (cap) {
        case Capability.INPUT:
        case Capability.OUTPUT:
        case Capability.PULL_UP:
            return true;
        default:
            return false;
    }
}

fn void? configure(Pin pin, Config config) {
    if (!is_valid(pin)) return INVALID_PIN~;
    if (config.direction == Direction.INPUT_OUTPUT || config.direction == Direction.DISABLED) return UNSUPPORTED_MODE~;
    if (config.pull == Pull.DOWN || config.pull == Pull.UP_DOWN) return UNSUPPORTED_PULL~;
    if (config.output_type == OutputType.OPEN_DRAIN) return UNSUPPORTED_DRIVE~;
    if (config.drive_strength != DriveStrength.DEFAULT) return UNSUPPORTED_DRIVE~;

    disable_pwm(pin);
    char bit = get_bit(pin);
    char ddr = get_ddr(pin);
    char port = get_port(pin);

    switch (config.direction) {
        case Direction.OUTPUT:
            if (config.pull != Pull.NONE) return UNSUPPORTED_PULL~;
            if (config.initial_state == PinState.HIGH) {
                reg_set(port, bit);
            } else {
                reg_clr(port, bit);
            }
            reg_set(ddr, bit);
        case Direction.INPUT:
            reg_clr(ddr, bit);
            if (config.pull == Pull.UP) {
                reg_set(port, bit);
            } else {
                reg_clr(port, bit);
            }
        default:
            return UNSUPPORTED_MODE~;
    }
}

// Does not touch the timers: `configure()` and `reset()` already take the pin
// away from a PWM output, so doing it again here would only slow the hot path.
fn void? write(Pin pin, PinState state) {
    if (!is_valid(pin)) return INVALID_PIN~;
    char bit = get_bit(pin);
    char port = get_port(pin);
    if (state != PinState.LOW) {
        reg_set(port, bit);
    } else {
        reg_clr(port, bit);
    }
}

fn PinState? read(Pin pin) {
    if (!is_valid(pin)) return INVALID_PIN~;
    char bit = get_bit(pin);
    char pin_reg = get_pin_reg(pin);
    return (reg_read(pin_reg) & (char)(1 << bit)) != 0 ? PinState.HIGH : PinState.LOW;
}

fn void? toggle(Pin pin) {
    PinState state = read_output(pin)!;
    write(pin, state == PinState.HIGH ? PinState.LOW : PinState.HIGH)!;
}

fn PinState? read_output(Pin pin) {
    if (!is_valid(pin)) return INVALID_PIN~;
    char bit = get_bit(pin);
    char port = get_port(pin);
    return (reg_read(port) & (char)(1 << bit)) != 0 ? PinState.HIGH : PinState.LOW;
}

fn void? reset(Pin pin) {
    if (!is_valid(pin)) return INVALID_PIN~;
    disable_pwm(pin);
    char bit = get_bit(pin);
    reg_clr(get_ddr(pin), bit);
    reg_clr(get_port(pin), bit);
}

// Handles. Each AVR port is three consecutive I/O registers, PINx, DDRx and
// PORTx, so caching the PINx address and the bit mask is enough. Writing a 1
// to a PINx bit toggles the matching PORTx bit in hardware (ATmega328P
// datasheet, 14.2.2), which makes `toggle()` a single store with no
// read-modify-write.

struct Output {
    char pin_reg;
    char mask;
}

struct Input {
    char pin_reg;
    char mask;
}

macro char* reg_ptr(char addr) @local => (char*)(uptr)addr;

fn Output? output(Pin pin, PinState initial = PinState.LOW) @inline {
    configure(pin, { .direction = Direction.OUTPUT, .initial_state = initial })!;
    return { get_pin_reg(pin), (char)(1 << get_bit(pin)) };
}

fn Input? input(Pin pin, Pull pull = Pull.NONE) @inline {
    configure(pin, { .direction = Direction.INPUT, .pull = pull })!;
    return { get_pin_reg(pin), (char)(1 << get_bit(pin)) };
}

fn void Output.set(self) @inline {
    char* port = reg_ptr(self.pin_reg + regs::PORT_FROM_PIN);
    @volatile_store(*port, (char)(@volatile_load(*port) | self.mask));
}

fn void Output.clear(self) @inline {
    char* port = reg_ptr(self.pin_reg + regs::PORT_FROM_PIN);
    @volatile_store(*port, (char)(@volatile_load(*port) & ~self.mask));
}

fn void Output.toggle(self) @inline {
    @volatile_store(*reg_ptr(self.pin_reg), self.mask);
}

fn void Output.write(self, PinState state) @inline {
    if (state != PinState.LOW) {
        self.set();
    } else {
        self.clear();
    }
}

fn PinState Output.read(self) @inline {
    return (@volatile_load(*reg_ptr(self.pin_reg + regs::PORT_FROM_PIN)) & self.mask) != 0 ? PinState.HIGH : PinState.LOW;
}

fn PinState Input.read(self) @inline {
    return (@volatile_load(*reg_ptr(self.pin_reg)) & self.mask) != 0 ? PinState.HIGH : PinState.LOW;
}

fn bool Input.is_high(self) @inline => self.read() == PinState.HIGH;
fn bool Input.is_low(self) @inline => self.read() == PinState.LOW;
