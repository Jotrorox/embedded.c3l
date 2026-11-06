module embedded::time;

import embedded::backends::esp32::esp32c3::regs;

const ulong ULONG_MAX_VALUE = 0xFFFF_FFFF_FFFF_FFFF;
const ulong MAX_MS_VALUE = ULONG_MAX_VALUE / 1000;
const ulong MAX_SECONDS_VALUE = ULONG_MAX_VALUE / 1_000_000;

bool delay_timer_ready @local = false;

fn void reg_write(uint addr, uint value) {
    @volatile_store(*(uint*)addr, value);
}

fn uint reg_read(uint addr) {
    return @volatile_load(*(uint*)addr);
}

fn ulong systimer_unit0_read_count() {
    reg_write(regs::SYSTIMER_UNIT0_OP, regs::SYSTIMER_UNIT0_VALUE_VALID);
    reg_write(regs::SYSTIMER_UNIT0_OP, regs::SYSTIMER_UNIT0_UPDATE);
    while ((reg_read(regs::SYSTIMER_UNIT0_OP) & regs::SYSTIMER_UNIT0_VALUE_VALID) == 0) {}

    uint lo = reg_read(regs::SYSTIMER_UNIT0_VALUE_LO);
    uint hi = reg_read(regs::SYSTIMER_UNIT0_VALUE_HI) & regs::SYSTIMER_UNIT0_VALUE_HI_MASK;
    return ((ulong)hi << 32) | lo;
}

fn void delay_timer_init() {
    reg_write(regs::SYSTEM_PERIP_CLK_EN0, reg_read(regs::SYSTEM_PERIP_CLK_EN0) | regs::PERIP_SYSTIMER);
    reg_write(regs::SYSTEM_PERIP_RST_EN0, reg_read(regs::SYSTEM_PERIP_RST_EN0) & ~regs::PERIP_SYSTIMER);

    uint cfg = reg_read(regs::SYSTIMER_CONF);
    cfg |= regs::SYSTIMER_CONF_CLK_EN;
    cfg |= regs::SYSTIMER_CONF_UNIT0_WORK_EN;
    cfg &= ~regs::SYSTIMER_CONF_UNIT0_CORE0_STALL_EN;
    reg_write(regs::SYSTIMER_CONF, cfg);

    delay_timer_ready = true;
}

fn void delay_timer_ensure_init() {
    if (!delay_timer_ready) delay_timer_init();
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
    delay_timer_ensure_init();

    // ESP32-C3 systimer runs at 16 MHz in the reference implementation.
    return systimer_unit0_read_count() >> 4;
}

fn ClockInfo clock_info() {
    return { 1_000_000, 1, true, true };
}

fn Duration us(ulong value) {
    return { value };
}

// The range check makes the multiplication exact.
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

// Polls the systimer. Idling with `wfi` would need a systimer alarm
// interrupt to wake up, which the library does not set up.
fn void sleep_until(Instant deadline) {
    while (!has_elapsed(deadline)) asm("nop");
}

// The systimer counts on its own, so polling it works with interrupts off.
fn void spin(Duration duration) {
    if (duration_is_zero(duration)) return;
    Instant deadline = deadline_after(duration);
    while (!has_elapsed(deadline)) asm("nop");
}
