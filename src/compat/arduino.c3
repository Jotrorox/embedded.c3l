module embedded::compat::arduino;

import embedded::gpio;
import embedded::time;

fn void pin_mode(gpio::Pin pin, PinMode mode) {
    switch (mode) {
        case PinMode.OUTPUT:         (void)gpio::configure(pin, gpio::CONFIG_OUTPUT_LOW);
        case PinMode.INPUT:          (void)gpio::configure(pin, gpio::CONFIG_INPUT);
        case PinMode.INPUT_PULLUP:   (void)gpio::configure(pin, gpio::CONFIG_INPUT_PULLUP);
        case PinMode.INPUT_PULLDOWN: (void)gpio::configure(pin, gpio::CONFIG_INPUT_PULLDOWN);
        default:
    }
}

fn void digital_write(gpio::Pin pin, PinState state) {
    (void)gpio::write(pin, state);
}

fn PinState digital_read(gpio::Pin pin) {
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
    return time::as_ms(time::since_boot());
}

fn ulong micros() {
    return time::as_us(time::since_boot());
}
