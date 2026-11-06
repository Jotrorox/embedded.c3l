module embedded::exti;

import embedded::gpio;
import embedded::irq;
import embedded::backends::esp32::esp32c3::soc;

// All GPIO interrupts share the GPIO source. GPIO_STATUS has one pending bit
// per pin, cleared through GPIO_STATUS_W1TC.
const uint GPIO_STATUS      = soc::GPIO_BASE + 0x044;
const uint GPIO_STATUS_W1TC = soc::GPIO_BASE + 0x04C;

// GPIO_PINn_REG fields.
const uint PIN_INT_TYPE_SHIFT = 7;
const uint PIN_INT_TYPE_MASK  = 0x7u << PIN_INT_TYPE_SHIFT;
const uint PIN_INT_ENA_CPU    = 1u << 13;
const uint PIN_INT_ENA_MASK   = 0x1Fu << 13;

// INT_TYPE values.
const uint INT_TYPE_RISING     = 1;
const uint INT_TYPE_FALLING    = 2;
const uint INT_TYPE_ANY_EDGE   = 3;
const uint INT_TYPE_LOW_LEVEL  = 4;
const uint INT_TYPE_HIGH_LEVEL = 5;

const uint PIN_COUNT = 22;

irq::Handler[PIN_COUNT] handlers @local;
bool source_attached @local = false;

fn bool supports(gpio::Pin pin, Trigger trigger) {
    return gpio::is_valid(pin) && (uint)trigger <= (uint)Trigger.HIGH_LEVEL;
}

fn void? attach(gpio::Pin pin, Trigger trigger, irq::Handler handler) {
    if (!gpio::is_valid(pin)) return PIN_NOT_INTERRUPT_CAPABLE~;

    uint type;
    switch (trigger) {
        case Trigger.RISING:     type = INT_TYPE_RISING;
        case Trigger.FALLING:    type = INT_TYPE_FALLING;
        case Trigger.BOTH_EDGES: type = INT_TYPE_ANY_EDGE;
        case Trigger.LOW_LEVEL:  type = INT_TYPE_LOW_LEVEL;
        case Trigger.HIGH_LEVEL: type = INT_TYPE_HIGH_LEVEL;
        default: return UNSUPPORTED_TRIGGER~;
    }

    if (!source_attached) {
        irq::attach(irq::Source.GPIO, &dispatch)!;
        source_attached = true;
    }

    uint mask = 1u << (uint)pin;
    irq::@critical() {
        soc::modify(soc::pin_reg(pin), PIN_INT_TYPE_MASK | PIN_INT_ENA_MASK, 0);
        handlers[(uint)pin] = handler;
        soc::write(GPIO_STATUS_W1TC, mask);
        soc::modify(soc::pin_reg(pin), PIN_INT_TYPE_MASK | PIN_INT_ENA_MASK,
            (type << PIN_INT_TYPE_SHIFT) | PIN_INT_ENA_CPU);
    };
}

fn void detach(gpio::Pin pin) {
    if (!gpio::is_valid(pin)) return;
    irq::@critical() {
        soc::modify(soc::pin_reg(pin), PIN_INT_TYPE_MASK | PIN_INT_ENA_MASK, 0);
        soc::write(GPIO_STATUS_W1TC, 1u << (uint)pin);
        handlers[(uint)pin] = null;
    };
}

// Clears each pending pin before calling its handler, so an edge that arrives
// while the handler runs is not lost. A level trigger whose level persists
// fires again right after the handler returns.
fn void dispatch() @local {
    uint pending = soc::read(GPIO_STATUS);
    soc::write(GPIO_STATUS_W1TC, pending);
    for (uint pin = 0; pin < PIN_COUNT; pin++) {
        if ((pending & (1u << pin)) == 0) continue;
        irq::Handler handler = handlers[pin];
        if (handler) handler();
    }
}
