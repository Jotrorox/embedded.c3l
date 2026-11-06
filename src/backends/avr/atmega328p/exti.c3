module embedded::exti;

import embedded::gpio;
import embedded::irq;
import embedded::backends::avr::atmega328p::soc;

// INT0 is on PD2 (Uno D2), INT1 on PD3 (Uno D3).
const uint EIFR  = 0x3C;
const uint EIMSK = 0x3D;
const uint EICRA = 0x69;

// EICRA sense control, two bits per line (ISCn1:ISCn0).
const char ISC_LOW_LEVEL = 0;
const char ISC_ANY_EDGE  = 1;
const char ISC_FALLING   = 2;
const char ISC_RISING    = 3;

irq::Handler[2] handlers @local;

fn int line_of(gpio::Pin pin) @local {
    switch ((uint)pin) {
        case 2: return 0;
        case 3: return 1;
        default: return -1;
    }
}

fn bool supports(gpio::Pin pin, Trigger trigger) {
    return line_of(pin) >= 0 && trigger != Trigger.HIGH_LEVEL;
}

fn void? attach(gpio::Pin pin, Trigger trigger, irq::Handler handler) {
    int line = line_of(pin);
    if (line < 0) return PIN_NOT_INTERRUPT_CAPABLE~;

    char sense;
    switch (trigger) {
        case Trigger.RISING:     sense = ISC_RISING;
        case Trigger.FALLING:    sense = ISC_FALLING;
        case Trigger.BOTH_EDGES: sense = ISC_ANY_EDGE;
        case Trigger.LOW_LEVEL:  sense = ISC_LOW_LEVEL;
        default: return UNSUPPORTED_TRIGGER~;
    }

    char bit = (char)(1 << line);
    char shift = (char)(line * 2);
    irq::@critical() {
        soc::clear8(EIMSK, bit);
        handlers[line] = handler;
        soc::write8(EICRA, (soc::read8(EICRA) & (char)~(0x03 << shift)) | (char)(sense << shift));
        // Writing a one clears the flag, so a stale edge does not fire at once.
        soc::write8(EIFR, bit);
        soc::set8(EIMSK, bit);
    };
}

fn void detach(gpio::Pin pin) {
    int line = line_of(pin);
    if (line < 0) return;
    irq::@critical() {
        soc::clear8(EIMSK, (char)(1 << line));
        handlers[line] = null;
    };
}

fn void dispatch(int line) @local @inline {
    irq::Handler handler = handlers[line];
    if (handler) handler();
}

fn void int0_handler() @export("embedded_avr_exti_int0") => dispatch(0);
fn void int1_handler() @export("embedded_avr_exti_int1") => dispatch(1);

// Weak so that firmware defining its own INT0/INT1 vector wins.
fn void __vector_1() @weak @naked @export("__vector_1") {
    irq::@isr("embedded_avr_exti_int0");
}

fn void __vector_2() @weak @naked @export("__vector_2") {
    irq::@isr("embedded_avr_exti_int1");
}
