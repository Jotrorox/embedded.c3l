module embedded::pwm;

import embedded::gpio;
import embedded::irq;
import embedded::backends::avr::atmega328p::soc;

// Timer 0 (shared with embedded::time, fast PWM, TOP 255, /64):
//   D6 = OC0A, D5 = OC0B
const uint TCCR0A = 0x44;
const uint OCR0A  = 0x47;
const uint OCR0B  = 0x48;
// Timer 1 (fast PWM mode 14, TOP = ICR1):
//   D9 = OC1A, D10 = OC1B
const uint TCCR1A = 0x80;
const uint TCCR1B = 0x81;
const uint ICR1   = 0x86;
const uint OCR1A  = 0x88;
const uint OCR1B  = 0x8A;
// Timer 2 (fast PWM mode 3, TOP 255):
//   D11 = OC2A, D3 = OC2B
const uint TCCR2A = 0xB0;
const uint TCCR2B = 0xB1;
const uint OCR2A  = 0xB3;
const uint OCR2B  = 0xB4;

// TCCRnA output-compare modes: COMnx1 set, COMnx0 clear = non-inverting.
const char COM_A_NONINVERTING = 1 << 7;
const char COM_B_NONINVERTING = 1 << 5;
const char COM_A_MASK = 0xC0;
const char COM_B_MASK = 0x30;
// Waveform generation.
const char TCCR1A_WGM11 = 1 << 1;
const char TCCR1B_WGM13_WGM12 = (1 << 4) | (1 << 3);
const char TCCR2A_FAST_PWM = 0x03;
const char CS_MASK = 0x07;

const uint TIMER0_HZ = soc::CPU_HZ / 64 / 256;
const uint DEFAULT_TIMER1_HZ = 1000;
const char DEFAULT_TIMER2_CS = 4; // /64, ~977 Hz like timer 0

struct Channel {
    char pin;
}

fn bool supports(gpio::Pin pin) {
    switch ((uint)pin) {
        case 3:
        case 5:
        case 6:
        case 9:
        case 10:
        case 11:
            return true;
        default:
            return false;
    }
}

fn char timer_of(char pin) @local {
    switch (pin) {
        case 5:
        case 6: return 0;
        case 9:
        case 10: return 1;
        default: return 2;
    }
}

fn uint tccra_of(char pin) @local {
    switch (timer_of(pin)) {
        case 0: return TCCR0A;
        case 1: return TCCR1A;
        default: return TCCR2A;
    }
}

// The output-compare channel is A for D6, D9, D11 and B for D5, D10, D3.
fn bool is_channel_a(char pin) @local => pin == 6 || pin == 9 || pin == 11;

fn char com_bits(char pin) @local => is_channel_a(pin) ? COM_A_NONINVERTING : COM_B_NONINVERTING;
fn char com_mask(char pin) @local => is_channel_a(pin) ? COM_A_MASK : COM_B_MASK;

fn uint ocr_of(char pin) @local {
    switch (pin) {
        case 6: return OCR0A;
        case 5: return OCR0B;
        case 9: return OCR1A;
        case 10: return OCR1B;
        case 11: return OCR2A;
        default: return OCR2B;
    }
}

// Timer 1 prescalers by CS1 value, and timer 2's (which has /32 and /128).
fn uint timer1_divider(char cs) @local {
    switch (cs) {
        case 1: return 1;
        case 2: return 8;
        case 3: return 64;
        case 4: return 256;
        default: return 1024;
    }
}

fn uint timer2_divider(char cs) @local {
    switch (cs) {
        case 1: return 1;
        case 2: return 8;
        case 3: return 32;
        case 4: return 64;
        case 5: return 128;
        case 6: return 256;
        default: return 1024;
    }
}

fn bool within_factor_two(uint actual, uint wanted) @local {
    return actual <= wanted * 2 && wanted <= actual * 2;
}

fn ushort timer1_top() @local {
    irq::State state = irq::save_and_disable();
    ushort top = soc::read16(ICR1);
    irq::restore(state);
    return top;
}

// Programs timer 1 for `hz` with the finest resolution (smallest prescaler)
// that fits TOP into 16 bits, keeping both channels' duty cycles.
fn uint? timer1_set_frequency(uint hz) @local {
    if (hz == 0 || hz > soc::CPU_HZ / 2) return UNSUPPORTED_FREQUENCY~;
    char cs = 0;
    uint top = 0;
    for (char candidate = 1; candidate <= 5; candidate++) {
        uint ticks = soc::CPU_HZ / timer1_divider(candidate) / hz;
        if (ticks >= 2 && ticks <= 65536) {
            cs = candidate;
            top = ticks - 1;
            break;
        }
    }
    if (cs == 0) return UNSUPPORTED_FREQUENCY~;

    irq::State state = irq::save_and_disable();
    defer irq::restore(state);
    bool running = (soc::read8(TCCR1B) & CS_MASK) != 0;
    uint old_top = running ? soc::read16(ICR1) : 0;
    uint ocr_a = running ? soc::read16(OCR1A) : 0;
    uint ocr_b = running ? soc::read16(OCR1B) : 0;

    soc::write8(TCCR1B, 0); // stop while reconfiguring
    soc::write8(TCCR1A, (soc::read8(TCCR1A) & (COM_A_MASK | COM_B_MASK)) | TCCR1A_WGM11);
    soc::write16(ICR1, (ushort)top);
    if (old_top != 0) {
        soc::write16(OCR1A, (ushort)(ocr_a * top / old_top));
        soc::write16(OCR1B, (ushort)(ocr_b * top / old_top));
    }
    soc::write16(0x84, 0); // TCNT1
    soc::write8(TCCR1B, TCCR1B_WGM13_WGM12 | cs);
    return soc::CPU_HZ / timer1_divider(cs) / (top + 1);
}

// Picks timer 2's prescaler whose frequency is closest to `hz`.
fn uint? timer2_set_frequency(uint hz) @local {
    if (hz == 0) return UNSUPPORTED_FREQUENCY~;
    char best = 1;
    uint best_error = 0xFFFF_FFFF;
    for (char cs = 1; cs <= 7; cs++) {
        uint actual = soc::CPU_HZ / timer2_divider(cs) / 256;
        uint error = actual > hz ? actual - hz : hz - actual;
        if (error < best_error) {
            best = cs;
            best_error = error;
        }
    }
    uint actual = soc::CPU_HZ / timer2_divider(best) / 256;
    if (!within_factor_two(actual, hz)) return UNSUPPORTED_FREQUENCY~;
    soc::write8(TCCR2A, (soc::read8(TCCR2A) & (COM_A_MASK | COM_B_MASK)) | TCCR2A_FAST_PWM);
    soc::write8(TCCR2B, best);
    return actual;
}

fn Channel? open(gpio::Pin pin, Config config = {}) {
    if (!supports(pin)) return PIN_NOT_PWM_CAPABLE~;
    char p = (char)pin;
    switch (timer_of(p)) {
        case 0:
            if (config.frequency_hz != 0 && !within_factor_two(TIMER0_HZ, config.frequency_hz)) {
                return UNSUPPORTED_FREQUENCY~;
            }
        case 1:
            bool running = (soc::read8(TCCR1B) & CS_MASK) != 0;
            if (config.frequency_hz != 0) {
                timer1_set_frequency(config.frequency_hz)!;
            } else if (!running) {
                timer1_set_frequency(DEFAULT_TIMER1_HZ)!;
            }
        default:
            bool running = (soc::read8(TCCR2B) & CS_MASK) != 0;
            if (config.frequency_hz != 0) {
                timer2_set_frequency(config.frequency_hz)!;
            } else if (!running) {
                soc::write8(TCCR2A, (soc::read8(TCCR2A) & (COM_A_MASK | COM_B_MASK)) | TCCR2A_FAST_PWM);
                soc::write8(TCCR2B, DEFAULT_TIMER2_CS);
            }
    }
    // The compare unit only drives the pin while it is an output.
    gpio::configure(pin, gpio::CONFIG_OUTPUT_LOW)!;
    Channel channel = { p };
    channel.set_duty(config.duty_permille);
    return channel;
}

fn void Channel.set_duty(self, uint permille) {
    if (permille > MAX_DUTY) permille = MAX_DUTY;
    uint tccra = tccra_of(self.pin);
    if (permille == 0) {
        // Fast PWM still emits a one-clock pulse at OCR = 0, so disconnect the
        // compare unit and let the (low) output latch drive the pin.
        soc::clear8(tccra, com_mask(self.pin));
        return;
    }
    if (timer_of(self.pin) == 1) {
        uint top = timer1_top();
        irq::State state = irq::save_and_disable();
        soc::write16(ocr_of(self.pin), (ushort)(top * permille / MAX_DUTY));
        irq::restore(state);
    } else {
        // OCR = TOP (255) gives a steady high level.
        soc::write8(ocr_of(self.pin), (char)(255 * permille / MAX_DUTY));
    }
    soc::write8(tccra, (soc::read8(tccra) & (char)~com_mask(self.pin)) | com_bits(self.pin));
}

fn uint Channel.frequency(self) {
    switch (timer_of(self.pin)) {
        case 0: return TIMER0_HZ;
        case 1:
            char cs = soc::read8(TCCR1B) & CS_MASK;
            if (cs == 0) return 0;
            return soc::CPU_HZ / timer1_divider(cs) / ((uint)timer1_top() + 1);
        default:
            char cs = soc::read8(TCCR2B) & CS_MASK;
            if (cs == 0) return 0;
            return soc::CPU_HZ / timer2_divider(cs) / 256;
    }
}

fn uint? Channel.set_frequency(self, uint hz) {
    switch (timer_of(self.pin)) {
        case 0:
            if (!within_factor_two(TIMER0_HZ, hz)) return UNSUPPORTED_FREQUENCY~;
            return TIMER0_HZ;
        case 1: return timer1_set_frequency(hz);
        default: return timer2_set_frequency(hz);
    }
}

fn void Channel.close(self) {
    soc::clear8(tccra_of(self.pin), com_mask(self.pin));
    (void)gpio::reset((gpio::Pin)self.pin);
}
