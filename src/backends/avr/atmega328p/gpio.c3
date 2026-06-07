module embedded::gpio;

fn char get_port(Pin pin) {
    if ((int)pin <= 7) return 0x2B;
    if ((int)pin <= 13) return 0x25;
    return 0x28;
}

fn char get_ddr(Pin pin) {
    if ((int)pin <= 7) return 0x2A;
    if ((int)pin <= 13) return 0x24;
    return 0x27;
}

fn char get_pin_reg(Pin pin) {
    if ((int)pin <= 7) return 0x29;
    if ((int)pin <= 13) return 0x23;
    return 0x26;
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
        case (Pin)3:  reg_clr_mask(0xB0, 0x30);
        case (Pin)5:  reg_clr_mask(0x44, 0x30);
        case (Pin)6:  reg_clr_mask(0x44, 0xC0);
        case (Pin)9:  reg_clr_mask(0x80, 0xC0);
        case (Pin)10: reg_clr_mask(0x80, 0x30);
        case (Pin)11: reg_clr_mask(0xB0, 0xC0);
        default:
    }
}

fn void pin_mode(Pin pin, PinMode mode) {
    if ((int)pin < 0 || (int)pin >= 20) return;
    disable_pwm(pin);
    char bit = get_bit(pin);
    char ddr = get_ddr(pin);
    char port = get_port(pin);
    switch (mode) {
        case PinMode.OUTPUT:
            reg_set(ddr, bit);
        case PinMode.INPUT:
            reg_clr(ddr, bit);
            reg_clr(port, bit);
        case PinMode.INPUT_PULLUP:
            reg_clr(ddr, bit);
            reg_set(port, bit);
        default:
    }
}

fn void digital_write(Pin pin, PinState state) {
    if ((int)pin < 0 || (int)pin >= 20) return;
    disable_pwm(pin);
    char bit = get_bit(pin);
    char port = get_port(pin);
    if (state != PinState.LOW) {
        reg_set(port, bit);
    } else {
        reg_clr(port, bit);
    }
}

fn PinState digital_read(Pin pin) {
    if ((int)pin < 0 || (int)pin >= 20) return PinState.LOW;
    char bit = get_bit(pin);
    char pin_reg = get_pin_reg(pin);
    return (reg_read(pin_reg) & (char)(1 << bit)) != 0 ? PinState.HIGH : PinState.LOW;
}
