module embedded::gpio @feat(MCU_ATMEGA328P);

// Arduino pin numbers to ATmega328P ports: D0-D7 are PD0-PD7, D8-D13 are
// PB0-PB5, A0-A5 (14-19) are PC0-PC5. Addresses are the I/O registers in
// data space (datasheet section 36, register summary).

const char PINB = 0x23;
const char PINC = 0x26;
const char PIND = 0x29;

fn void valid_pins() @test {
    for (int p = 0; p < 20; p++) assert(is_valid((Pin)p), "pin %d", p);
    assert(!is_valid((Pin)20));
    assert(!is_valid((Pin)0xFFFF));
}

fn void pin_decode_table() @test {
    for (int p = 0; p < 20; p++) {
        char pin_reg = p <= 7 ? PIND : p <= 13 ? PINB : PINC;
        char bit = (char)(p <= 7 ? p : p <= 13 ? p - 8 : p - 14);
        assert(get_pin_reg((Pin)p) == pin_reg, "PINx of pin %d", p);
        assert(get_ddr((Pin)p) == pin_reg + 1, "DDRx of pin %d", p);
        assert(get_port((Pin)p) == pin_reg + 2, "PORTx of pin %d", p);
        assert(get_bit((Pin)p) == bit, "bit of pin %d", p);
    }
}

fn void capabilities() @test {
    assert(supports((Pin)13, Capability.INPUT));
    assert(supports((Pin)13, Capability.OUTPUT));
    assert(supports((Pin)13, Capability.PULL_UP));
    assert(!supports((Pin)13, Capability.PULL_DOWN), "no pull-down on the ATmega328P");
    assert(!supports((Pin)13, Capability.OPEN_DRAIN));
    assert(!supports((Pin)20, Capability.INPUT), "invalid pin");
}
