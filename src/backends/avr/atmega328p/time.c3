module embedded::time;

const uint TCCR0A = 0x44;
const uint TCCR0B = 0x45;
const uint TCNT0  = 0x46;
const uint TIMSK0 = 0x6E;
const uint TIFR0  = 0x35;
const uint SREG   = 0x5F;

const char WGM01_WGM00 = 0x03;
const char CS00_CS01   = 0x03;
const char TOIE0_BIT   = 0x01;
const char TOV0_BIT    = 0x01;

const uint MILLIS_INC = 1;
const char FRACT_INC = 3;
const char FRACT_MAX = 125;
const ulong ULONG_MAX_VALUE = 0xFFFF_FFFF_FFFF_FFFF;
const ulong MAX_MS_VALUE = 18_446_744_073_709_551;
const ulong MAX_SECONDS_VALUE = 18_446_744_073_709;

uint timer0_overflow_count = 0;
uint timer0_millis = 0;
char timer0_fract = 0;
bool timer0_time_active = false;

fn void reg_write(uint addr, char val) {
    @volatile_store(*(char*)(uptr)addr, val);
}

fn char reg_read(uint addr) {
    return @volatile_load(*(char*)(uptr)addr);
}

fn void reg_set(uint addr, char mask) {
    reg_write(addr, (char)(reg_read(addr) | mask));
}

fn void embedded_avr_time_init() @export("embedded_avr_time_init") {
    if (timer0_time_active) return;

    reg_set(TCCR0A, WGM01_WGM00);
    reg_write(TCCR0B, (char)((reg_read(TCCR0B) & (char)0xF8) | CS00_CS01));
    reg_set(TIMSK0, TOIE0_BIT);
    asm("sei");
    timer0_time_active = true;
}

fn Duration scale_duration_saturating(ulong value, uint factor) {
    ulong result = 0;
    ulong addend = value;
    uint remaining = factor;

    while (remaining > 0) {
        if ((remaining & 1) != 0) {
            if (ULONG_MAX_VALUE - result < addend) return { ULONG_MAX_VALUE };
            result += addend;
        }
        remaining >>= 1;
        if (remaining > 0) {
            if (ULONG_MAX_VALUE - addend < addend) {
                addend = ULONG_MAX_VALUE;
            } else {
                addend += addend;
            }
        }
    }

    return { result };
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

    char old_sreg = reg_read(SREG);
    asm("cli");
    uint m = @volatile_load(timer0_overflow_count);
    char t = reg_read(TCNT0);
    if ((reg_read(TIFR0) & TOV0_BIT) != 0 && t < 255) {
        m++;
    }
    reg_write(SREG, old_sreg);

    return (ulong)(((m << 8) + (uint)t) << 2);
}

fn ClockInfo clock_info() {
    return { 1_000_000, 4, true, true };
}

fn Duration us(ulong value) {
    return { value };
}

fn Duration ms(ulong value) {
    if (value > MAX_MS_VALUE) return { ULONG_MAX_VALUE };
    return scale_duration_saturating(value, 1000);
}

fn Duration seconds(ulong value) {
    if (value > MAX_SECONDS_VALUE) return { ULONG_MAX_VALUE };
    return scale_duration_saturating(value, 1_000_000);
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

fn Duration elapsed_since(Instant start) {
    return elapsed_between(start, now());
}

fn Duration elapsed_between(Instant start, Instant end) {
    return { (ulong)(end.ticks - start.ticks) };
}

fn Instant deadline_after(Duration duration) {
    return { (Ticks)(now().ticks + duration.micros) };
}

fn bool has_elapsed(Instant deadline) {
    return (long)(now().ticks - deadline.ticks) >= 0;
}

fn void sleep(Duration duration) {
    if (duration_is_zero(duration)) return;
    sleep_until(deadline_after(duration));
}

fn void sleep_until(Instant deadline) {
    while (!has_elapsed(deadline)) {}
}

fn void timer0_ovf_impl() @export("timer0_ovf_impl") {
    uint m = @volatile_load(timer0_millis);
    char f = @volatile_load(timer0_fract);

    m += MILLIS_INC;
    f += FRACT_INC;
    if (f >= FRACT_MAX) {
        f -= FRACT_MAX;
        m += 1;
    }

    @volatile_store(timer0_fract, f);
    @volatile_store(timer0_millis, m);
    @volatile_store(timer0_overflow_count, (uint)(@volatile_load(timer0_overflow_count) + 1));
}

fn void __vector_16() @naked @export("__vector_16") {
    asm("push r0");
    asm("in r0, 0x3f");
    asm("push r0");
    asm("push r1");
    asm("eor r1, r1");
    asm("push r18");
    asm("push r19");
    asm("push r20");
    asm("push r21");
    asm("push r22");
    asm("push r23");
    asm("push r24");
    asm("push r25");
    asm("push r26");
    asm("push r27");
    asm("push r30");
    asm("push r31");
    asm("rcall timer0_ovf_impl");
    asm("pop r31");
    asm("pop r30");
    asm("pop r27");
    asm("pop r26");
    asm("pop r25");
    asm("pop r24");
    asm("pop r23");
    asm("pop r22");
    asm("pop r21");
    asm("pop r20");
    asm("pop r19");
    asm("pop r18");
    asm("pop r1");
    asm("pop r0");
    asm("out 0x3f, r0");
    asm("pop r0");
    asm("reti");
}
