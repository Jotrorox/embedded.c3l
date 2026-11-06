module embedded::time;

// The parts of `embedded::time` that are the same on every backend: duration
// arithmetic and deadlines. They only need the backend's `now()`, so they
// also build on the host, where test/ checks them against a fake clock.
//
// A backend still implements `clock_info()`, `now()`, `sleep_until()` and
// `spin()`.

const ulong ULONG_MAX_VALUE @private = 0xFFFF_FFFF_FFFF_FFFF;
const ulong MAX_MS_VALUE @private = ULONG_MAX_VALUE / 1000;
const ulong MAX_SECONDS_VALUE @private = ULONG_MAX_VALUE / 1_000_000;

// Deadlines are compared by the sign of the difference, so a duration of 2^63
// or more would look like the past. Clamp: 2^62 µs is ~146,000 years.
const ulong MAX_DEADLINE_US @private = (ulong)1 << 62;

// 64-by-32-bit long division. A plain `/` would call the 64-by-64-bit
// runtime helper, which is larger and slower on cores without a divider.
fn ulong div_u64_u32(ulong value, uint divisor) @private {
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

fn Duration since_boot() {
    return { (ulong)now().ticks };
}

fn Duration elapsed_since(Instant start) {
    return elapsed_between(start, now());
}

fn Duration elapsed_between(Instant start, Instant end) {
    return { (ulong)(end.ticks - start.ticks) };
}

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
