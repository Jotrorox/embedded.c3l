module embedded::exti @feat(MCU_ATMEGA328P);

import embedded::core;
import embedded::gpio;
import embedded::irq;
import embedded::backends::avr::atmega328p::regs;

// INT0 is on PD2 (Uno D2), INT1 on PD3 (Uno D3).


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
        case Trigger.RISING:     sense = regs::ISC_RISING;
        case Trigger.FALLING:    sense = regs::ISC_FALLING;
        case Trigger.BOTH_EDGES: sense = regs::ISC_ANY_EDGE;
        case Trigger.LOW_LEVEL:  sense = regs::ISC_LOW_LEVEL;
        default: return UNSUPPORTED_TRIGGER~;
    }

    char bit = (char)(1 << line);
    char shift = (char)(line * 2);
    irq::@critical() {
        @reg_clear_bits(regs::EIMSK, bit);
        handlers[line] = handler;
        @reg_write(regs::EICRA, (@reg_read(regs::EICRA) & (char)~(regs::ISC_MASK << shift)) | (char)(sense << shift));
        // Writing a one clears the flag, so a stale edge does not fire at once.
        @reg_write(regs::EIFR, bit);
        @reg_set_bits(regs::EIMSK, bit);
    };
}

fn void detach(gpio::Pin pin) {
    int line = line_of(pin);
    if (line < 0) return;
    irq::@critical() {
        @reg_clear_bits(regs::EIMSK, (char)(1 << line));
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
