module embedded::exti @feat(MCU_ESP32C3);

import embedded::gpio;
import embedded::irq;
import embedded::backends::esp32::esp32c3::soc;
import embedded::backends::esp32::esp32c3::regs;

// All GPIO interrupts share the GPIO source. regs::GPIO_STATUS has one pending bit
// per pin, cleared through regs::GPIO_STATUS_W1TC.
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
        case Trigger.RISING:     type = regs::GPIO_INT_TYPE_RISING;
        case Trigger.FALLING:    type = regs::GPIO_INT_TYPE_FALLING;
        case Trigger.BOTH_EDGES: type = regs::GPIO_INT_TYPE_ANY_EDGE;
        case Trigger.LOW_LEVEL:  type = regs::GPIO_INT_TYPE_LOW_LEVEL;
        case Trigger.HIGH_LEVEL: type = regs::GPIO_INT_TYPE_HIGH_LEVEL;
        default: return UNSUPPORTED_TRIGGER~;
    }

    if (!source_attached) {
        irq::attach(irq::Source.GPIO, &dispatch)!;
        source_attached = true;
    }

    uint mask = 1u << (uint)pin;
    irq::@critical() {
        soc::modify(soc::pin_reg(pin), regs::GPIO_PIN_INT_TYPE_MASK | regs::GPIO_PIN_INT_ENA_MASK, 0);
        handlers[(uint)pin] = handler;
        soc::write(regs::GPIO_STATUS_W1TC, mask);
        soc::modify(soc::pin_reg(pin), regs::GPIO_PIN_INT_TYPE_MASK | regs::GPIO_PIN_INT_ENA_MASK,
            (type << regs::GPIO_PIN_INT_TYPE_SHIFT) | regs::GPIO_PIN_INT_ENA_CPU);
    };
}

fn void detach(gpio::Pin pin) {
    if (!gpio::is_valid(pin)) return;
    irq::@critical() {
        soc::modify(soc::pin_reg(pin), regs::GPIO_PIN_INT_TYPE_MASK | regs::GPIO_PIN_INT_ENA_MASK, 0);
        soc::write(regs::GPIO_STATUS_W1TC, 1u << (uint)pin);
        handlers[(uint)pin] = null;
    };
}

// Clears each pending pin before calling its handler, so an edge that arrives
// while the handler runs is not lost. A level trigger whose level persists
// fires again right after the handler returns.
fn void dispatch() @local {
    uint pending = soc::read(regs::GPIO_STATUS);
    soc::write(regs::GPIO_STATUS_W1TC, pending);
    for (uint pin = 0; pin < PIN_COUNT; pin++) {
        if ((pending & (1u << pin)) == 0) continue;
        irq::Handler handler = handlers[pin];
        if (handler) handler();
    }
}
