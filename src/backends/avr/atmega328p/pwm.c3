module embedded::pwm @feat(MCU_ATMEGA328P);

import embedded::core;
import embedded::gpio;
import embedded::irq;
import embedded::backends::avr::atmega328p::soc;
import embedded::backends::avr::atmega328p::regs;

// Timer 0 (shared with embedded::time, fast PWM, TOP 255, /64):
//   D6 = OC0A, D5 = OC0B
// Timer 1 (fast PWM mode 14, TOP = ICR1):
//   D9 = OC1A, D10 = OC1B
// Timer 2 (fast PWM mode 3, TOP 255):
//   D11 = OC2A, D3 = OC2B

// TCCRnA output-compare modes: COMnx1 set, COMnx0 clear = non-inverting.
const char COM_A_NONINVERTING = regs::COM_A1;
const char COM_B_NONINVERTING = regs::COM_B1;
// Waveform generation.
const char TCCR1B_WGM13_WGM12 = regs::WGM13 | regs::WGM12;
const char TCCR2A_FAST_PWM = regs::WGM21 | regs::WGM20;

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
        case 0: return regs::TCCR0A;
        case 1: return regs::TCCR1A;
        default: return regs::TCCR2A;
    }
}

// The output-compare channel is A for D6, D9, D11 and B for D5, D10, D3.
fn bool is_channel_a(char pin) @local => pin == 6 || pin == 9 || pin == 11;

fn char com_bits(char pin) @local => is_channel_a(pin) ? COM_A_NONINVERTING : COM_B_NONINVERTING;
fn char com_mask(char pin) @local => is_channel_a(pin) ? regs::COM_A_MASK : regs::COM_B_MASK;

fn uint ocr_of(char pin) @local {
    switch (pin) {
        case 6: return regs::OCR0A;
        case 5: return regs::OCR0B;
        case 9: return regs::OCR1A;
        case 10: return regs::OCR1B;
        case 11: return regs::OCR2A;
        default: return regs::OCR2B;
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
    ushort top = soc::read16(regs::ICR1);
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
    bool running = (@reg_read(regs::TCCR1B) & regs::CS_MASK) != 0;
    uint old_top = running ? soc::read16(regs::ICR1) : 0;
    uint ocr_a = running ? soc::read16(regs::OCR1A) : 0;
    uint ocr_b = running ? soc::read16(regs::OCR1B) : 0;

    @reg_write(regs::TCCR1B, 0); // stop while reconfiguring
    @reg_write(regs::TCCR1A, (@reg_read(regs::TCCR1A) & (regs::COM_A_MASK | regs::COM_B_MASK)) | regs::WGM11);
    soc::write16(regs::ICR1, (ushort)top);
    if (old_top != 0) {
        soc::write16(regs::OCR1A, (ushort)(ocr_a * top / old_top));
        soc::write16(regs::OCR1B, (ushort)(ocr_b * top / old_top));
    }
    soc::write16(regs::TCNT1, 0);
    @reg_write(regs::TCCR1B, TCCR1B_WGM13_WGM12 | cs);
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
    @reg_write(regs::TCCR2A, (@reg_read(regs::TCCR2A) & (regs::COM_A_MASK | regs::COM_B_MASK)) | TCCR2A_FAST_PWM);
    @reg_write(regs::TCCR2B, best);
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
            bool running = (@reg_read(regs::TCCR1B) & regs::CS_MASK) != 0;
            if (config.frequency_hz != 0) {
                timer1_set_frequency(config.frequency_hz)!;
            } else if (!running) {
                timer1_set_frequency(DEFAULT_TIMER1_HZ)!;
            }
        default:
            bool running = (@reg_read(regs::TCCR2B) & regs::CS_MASK) != 0;
            if (config.frequency_hz != 0) {
                timer2_set_frequency(config.frequency_hz)!;
            } else if (!running) {
                @reg_write(regs::TCCR2A, (@reg_read(regs::TCCR2A) & (regs::COM_A_MASK | regs::COM_B_MASK)) | TCCR2A_FAST_PWM);
                @reg_write(regs::TCCR2B, DEFAULT_TIMER2_CS);
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
        @reg_clear_bits(tccra, com_mask(self.pin));
        return;
    }
    if (timer_of(self.pin) == 1) {
        uint top = timer1_top();
        irq::State state = irq::save_and_disable();
        soc::write16(ocr_of(self.pin), (ushort)(top * permille / MAX_DUTY));
        irq::restore(state);
    } else {
        // OCR = TOP (255) gives a steady high level.
        @reg_write(ocr_of(self.pin), (char)(255 * permille / MAX_DUTY));
    }
    @reg_write(tccra, (@reg_read(tccra) & (char)~com_mask(self.pin)) | com_bits(self.pin));
}

fn uint Channel.frequency(self) {
    switch (timer_of(self.pin)) {
        case 0: return TIMER0_HZ;
        case 1:
            char cs = @reg_read(regs::TCCR1B) & regs::CS_MASK;
            if (cs == 0) return 0;
            return soc::CPU_HZ / timer1_divider(cs) / ((uint)timer1_top() + 1);
        default:
            char cs = @reg_read(regs::TCCR2B) & regs::CS_MASK;
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
    @reg_clear_bits(tccra_of(self.pin), com_mask(self.pin));
    (void)gpio::reset((gpio::Pin)self.pin);
}
