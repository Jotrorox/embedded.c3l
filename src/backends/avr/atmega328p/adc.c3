module embedded::adc;

import embedded::gpio;
import embedded::time;
import embedded::backends::avr::atmega328p::soc;

const uint ADCL   = 0x78;
const uint ADCH   = 0x79;
const uint ADCSRA = 0x7A;
const uint ADMUX  = 0x7C;
const uint DIDR0  = 0x7E;

// ADMUX: REFS1:0 in bits 7:6, MUX3:0 in bits 3:0.
const char REFS_AREF     = 0x00;
const char REFS_AVCC     = 0x40;
const char REFS_INTERNAL = 0xC0;
const char REFS_MASK     = 0xC0;
// ADCSRA
const char ADEN = 1 << 7;
const char ADSC = 1 << 6;
const char ADPS_128 = 0x07; // 16 MHz / 128 = 125 kHz, inside the 50-200 kHz window

// Uno A0..A5 are pins 14..19, ADC channels 0..5.
const uint FIRST_ANALOG_PIN = 14;
const uint CHANNEL_COUNT = 6;
const ulong REFERENCE_SETTLE_US = 5_000;

struct Input {
    char admux;
}

fn bool supports(gpio::Pin pin) => (uint)pin >= FIRST_ANALOG_PIN && (uint)pin < FIRST_ANALOG_PIN + CHANNEL_COUNT;
fn bool supports_reference(Reference reference) => (uint)reference <= (uint)Reference.EXTERNAL;
fn char resolution_bits() => 10;

fn uint full_scale_millivolts(Reference reference) {
    switch (reference) {
        case Reference.DEFAULT:  return 5000;
        case Reference.INTERNAL: return 1100;
        default: return 0;
    }
}

fn Input? open(gpio::Pin pin, Config config = {}) {
    if (!supports(pin)) return PIN_NOT_ANALOG_CAPABLE~;
    char refs;
    switch (config.reference) {
        case Reference.DEFAULT:  refs = REFS_AVCC;
        case Reference.INTERNAL: refs = REFS_INTERNAL;
        case Reference.EXTERNAL: refs = REFS_AREF;
        default: return UNSUPPORTED_REFERENCE~;
    }
    char channel = (char)((uint)pin - FIRST_ANALOG_PIN);
    // Release the pin from GPIO and switch off its digital input buffer.
    (void)gpio::reset(pin);
    soc::set8(DIDR0, (char)(1 << channel));
    soc::write8(ADCSRA, ADEN | ADPS_128);
    return { refs | channel };
}

fn ushort? read(gpio::Pin pin) {
    Input input = open(pin)!;
    return input.read();
}

fn ushort convert() @local {
    soc::set8(ADCSRA, ADSC);
    while ((soc::read8(ADCSRA) & ADSC) != 0) {}
    // ADCL must be read first: it locks ADCH until ADCH is read.
    char low = soc::read8(ADCL);
    return (ushort)soc::read8(ADCH) << 8 | low;
}

fn ushort Input.read(self) {
    char previous = soc::read8(ADMUX);
    soc::write8(ADMUX, self.admux);
    // After a reference change the AREF pin (100 nF on the Uno) has to charge
    // or discharge to the new level, which takes milliseconds; wait, then
    // discard one conversion.
    if ((previous & REFS_MASK) != (self.admux & REFS_MASK)) {
        time::spin(time::us(REFERENCE_SETTLE_US));
        (void)convert();
    }
    return convert();
}

fn uint Input.read_millivolts(self) {
    uint full_scale;
    switch (self.admux & REFS_MASK) {
        case REFS_AVCC:     full_scale = 5000;
        case REFS_INTERNAL: full_scale = 1100;
        default: return 0;
    }
    return (uint)self.read() * full_scale / 1023;
}
