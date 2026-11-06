module embedded::time;

import embedded::irq;
import embedded::backends::avr::atmega328p::soc;

// Timer 0 runs in fast PWM mode with a /64 prescaler: one count every 4 µs at
// 16 MHz and an overflow every 1024 µs. The overflow interrupt extends the
// 8-bit counter in software. The same timer drives PWM on D5/D6, which is why
// `embedded::pwm` cannot change their frequency.
const uint TCCR0A = 0x44;
const uint TCCR0B = 0x45;
const uint TCNT0  = 0x46;
const uint TIMSK0 = 0x6E;
const uint TIFR0  = 0x35;
const uint SMCR   = 0x53;

const char WGM01_WGM00 = 0x03;
const char CS00_CS01   = 0x03;
const char TOIE0_BIT   = 0x01;
const char TOV0_BIT    = 0x01;
const char SMCR_SE     = 0x01; // sleep enable; SM2..0 = 000 selects idle mode

const ulong ULONG_MAX_VALUE = 0xFFFF_FFFF_FFFF_FFFF;
const ulong MAX_MS_VALUE = ULONG_MAX_VALUE / 1000;
const ulong MAX_SECONDS_VALUE = ULONG_MAX_VALUE / 1_000_000;

// `sleep_until()` idles the core between timer interrupts only while the
// deadline is more than two overflow periods away, so the final stretch is
// timed by polling and keeps the 4 µs resolution.
const long IDLE_THRESHOLD_US = 2048;

// `spin()` counts a 4-cycle loop: 4 iterations per microsecond at 16 MHz.
const uint SPIN_LOOPS_PER_US = soc::CPU_HZ / 1_000_000 / 4;
const ulong SPIN_CHUNK_US = 16_000;

uint timer0_overflow_count = 0;
bool timer0_time_active = false;

fn void embedded_avr_time_init() @export("embedded_avr_time_init") {
    if (timer0_time_active) return;

    soc::set8(TCCR0A, WGM01_WGM00);
    soc::write8(TCCR0B, (soc::read8(TCCR0B) & (char)0xF8) | CS00_CS01);
    soc::set8(TIMSK0, TOIE0_BIT);
    timer0_time_active = true;
    irq::enable();
}

fn ulong div_u64_u32(ulong value, uint divisor) {
    ulong quotient = 0;
    ulong remainder = 0;
    int bit = 63;

    while (bit >= 0) {
        remainder = (remainder << 1) | ((value >> bit) & 1);
        if (remainder >= (ulong)divisor) {
            remainder -= (ulong)divisor;
            quotient |= (ulong)1 << bit;
        }
        bit--;
    }

    return quotient;
}

fn ulong read_micros() {
    embedded_avr_time_init();

    irq::State state = irq::save_and_disable();
    uint m = @volatile_load(timer0_overflow_count);
    char t = soc::read8(TCNT0);
    if ((soc::read8(TIFR0) & TOV0_BIT) != 0 && t < 255) {
        m++;
    }
    irq::restore(state);

    // Widen first: in 32 bits this would wrap after 2^32 µs (71.6 min) and
    // deadlines spanning the wrap would never expire.
    return (((ulong)m << 8) | (ulong)t) << 2;
}

fn ClockInfo clock_info() {
    return { 1_000_000, 4, true, true };
}

fn Duration us(ulong value) {
    return { value };
}

// The range check makes the multiplication exact, so no saturating loop is
// needed. It is still a 64-bit multiply, which costs a few hundred cycles on
// an 8-bit core; keep `ms()`/`seconds()` out of tight loops where it matters.
fn Duration ms(ulong value) {
    if (value > MAX_MS_VALUE) return { ULONG_MAX_VALUE };
    return { value * 1000 };
}

fn Duration seconds(ulong value) {
    if (value > MAX_SECONDS_VALUE) return { ULONG_MAX_VALUE };
    return { value * 1_000_000 };
}

fn ulong as_us(Duration duration) {
    return duration.micros;
}

fn ulong as_ms(Duration duration) {
    return div_u64_u32(duration.micros, 1000);
}

fn Duration duration_add(Duration lhs, Duration rhs) {
    if (ULONG_MAX_VALUE - lhs.micros < rhs.micros) return { ULONG_MAX_VALUE };
    return { lhs.micros + rhs.micros };
}

fn Duration duration_sub_saturating(Duration lhs, Duration rhs) {
    if (lhs.micros < rhs.micros) return { 0 };
    return { lhs.micros - rhs.micros };
}

fn bool duration_is_zero(Duration duration) {
    return duration.micros == 0;
}

fn Instant now() {
    return { (Ticks)read_micros() };
}

fn Duration since_boot() {
    return { (ulong)now().ticks };
}

fn Duration elapsed_since(Instant start) {
    return elapsed_between(start, now());
}

fn Duration elapsed_between(Instant start, Instant end) {
    return { (ulong)(end.ticks - start.ticks) };
}

// Deadlines are compared by the sign of the difference, so a duration of 2^63
// or more would look like the past. Clamp: 2^62 µs is ~146,000 years.
const ulong MAX_DEADLINE_US = (ulong)1 << 62;

fn Instant deadline_after(Duration duration) {
    ulong micros = duration.micros > MAX_DEADLINE_US ? MAX_DEADLINE_US : duration.micros;
    return { (Ticks)(now().ticks + micros) };
}

fn bool has_elapsed(Instant deadline) {
    return (long)(now().ticks - deadline.ticks) >= 0;
}

fn void sleep(Duration duration) {
    if (duration_is_zero(duration)) return;
    sleep_until(deadline_after(duration));
}

fn void sleep_until(Instant deadline) {
    while (true) {
        long remaining = (long)(deadline.ticks - now().ticks);
        if (remaining <= 0) return;
        // With interrupts off the timer cannot wake the core (and the clock
        // stops advancing after one missed overflow), so only idle when they
        // are on. Any interrupt ends the idle period early, which is harmless.
        if (remaining > IDLE_THRESHOLD_US && irq::is_enabled()) {
            soc::write8(SMCR, SMCR_SE);
            asm("sleep");
            soc::write8(SMCR, 0);
        }
    }
}

// Busy-waits for `count` iterations of a 4-cycle loop. `count` arrives in
// r24:r25 (avr-gcc calling convention) and must not be zero. Exported so the
// optimiser keeps the argument even though only the asm reads it.
fn void spin_loop_4(ushort count) @naked @noinline @export("embedded_avr_spin_loop_4") {
    asm("1: sbiw r24, 1");
    asm("brne 1b");
    asm("ret");
}

fn void spin(Duration duration) {
    ulong remaining = duration.micros;
    while (remaining > SPIN_CHUNK_US) {
        spin_loop_4((ushort)(SPIN_CHUNK_US * SPIN_LOOPS_PER_US));
        remaining -= SPIN_CHUNK_US;
    }
    if (remaining != 0) spin_loop_4((ushort)(remaining * SPIN_LOOPS_PER_US));
}

fn void timer0_ovf_impl() @export("embedded_avr_timer0_ovf") {
    @volatile_store(timer0_overflow_count, @volatile_load(timer0_overflow_count) + 1);
}

fn void __vector_16() @naked @export("__vector_16") {
    irq::@isr("embedded_avr_timer0_ovf");
}
