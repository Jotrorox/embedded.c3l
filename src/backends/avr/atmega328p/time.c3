module embedded::time @feat(MCU_ATMEGA328P);

import embedded::irq;
import embedded::backends::avr::atmega328p::soc;
import embedded::backends::avr::atmega328p::regs;

// Timer 0 runs in fast PWM mode with a /64 prescaler: one count every 4 µs at
// 16 MHz and an overflow every 1024 µs. The overflow interrupt extends the
// 8-bit counter in software. The same timer drives PWM on D5/D6, which is why
// `embedded::pwm` cannot change their frequency.

const char WGM01_WGM00 = regs::WGM01 | regs::WGM00; // fast PWM, TOP 0xFF
const char CS00_CS01   = regs::CS01 | regs::CS00;   // clk/64

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

    soc::set8(regs::TCCR0A, WGM01_WGM00);
    soc::write8(regs::TCCR0B, (soc::read8(regs::TCCR0B) & (char)~regs::CS_MASK) | CS00_CS01);
    soc::set8(regs::TIMSK0, regs::TOIE0);
    timer0_time_active = true;
    irq::enable();
}

fn ulong read_micros() {
    embedded_avr_time_init();

    irq::State state = irq::save_and_disable();
    uint m = @volatile_load(timer0_overflow_count);
    char t = soc::read8(regs::TCNT0);
    if ((soc::read8(regs::TIFR0) & regs::TOV0) != 0 && t < 255) {
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

// Duration arithmetic, deadlines and `sleep()` are in src/api/time_common.c3.
fn Instant now() {
    return { (Ticks)read_micros() };
}

fn void sleep_until(Instant deadline) {
    while (true) {
        long remaining = (long)(deadline.ticks - now().ticks);
        if (remaining <= 0) return;
        // With interrupts off the timer cannot wake the core (and the clock
        // stops advancing after one missed overflow), so only idle when they
        // are on. Any interrupt ends the idle period early, which is harmless.
        if (remaining > IDLE_THRESHOLD_US && irq::is_enabled()) {
            soc::write8(regs::SMCR, regs::SMCR_SE);
            asm("sleep");
            soc::write8(regs::SMCR, 0);
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
