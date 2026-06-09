module embedded::compat::arduino;

import embedded::gpio;
import embedded::time;

fn void pin_mode(gpio::Pin pin, PinMode mode) {
    switch (mode) {
        case PinMode.OUTPUT:
            (void)gpio::configure(pin, { gpio::Direction.OUTPUT, gpio::Pull.NONE, gpio::OutputType.PUSH_PULL, gpio::DriveStrength.DEFAULT, gpio::PinState.LOW });
        case PinMode.INPUT:
            (void)gpio::configure(pin, { gpio::Direction.INPUT, gpio::Pull.NONE, gpio::OutputType.PUSH_PULL, gpio::DriveStrength.DEFAULT, gpio::PinState.LOW });
        case PinMode.INPUT_PULLUP:
            (void)gpio::configure(pin, { gpio::Direction.INPUT, gpio::Pull.UP, gpio::OutputType.PUSH_PULL, gpio::DriveStrength.DEFAULT, gpio::PinState.LOW });
        case PinMode.INPUT_PULLDOWN:
            (void)gpio::configure(pin, { gpio::Direction.INPUT, gpio::Pull.DOWN, gpio::OutputType.PUSH_PULL, gpio::DriveStrength.DEFAULT, gpio::PinState.LOW });
        default:
    }
}

fn void digital_write(gpio::Pin pin, gpio::PinState state) {
    (void)gpio::write(pin, state);
}

fn gpio::PinState digital_read(gpio::Pin pin) {
    if (try state = gpio::read(pin)) return state;
    return gpio::PinState.LOW;
}

fn void delay(ulong milliseconds) {
    time::sleep(time::ms(milliseconds));
}

fn void delay_ms(ulong milliseconds) {
    delay(milliseconds);
}

fn void delay_us(ulong microseconds) {
    time::sleep(time::us(microseconds));
}

fn void delay_microseconds(ulong microseconds) {
    delay_us(microseconds);
}

fn void delayMicroseconds(ulong microseconds) {
    delay_us(microseconds);
}

fn ulong millis() {
    time::Instant boot = { (time::Ticks)0 };
    return time::as_ms(time::elapsed_since(boot));
}

fn ulong micros() {
    time::Instant boot = { (time::Ticks)0 };
    return time::as_us(time::elapsed_since(boot));
}
