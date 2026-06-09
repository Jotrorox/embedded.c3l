module embedded::time;

const uint SYSTIMER_BASE = 0x6002_3000;
const uint TIMG0_BASE = 0x6001_F000;
const uint SYSTEM_BASE = 0x600C_0000;

const uint SYSTIMER_CONF = SYSTIMER_BASE + 0x0000;
const uint SYSTIMER_UNIT0_OP = SYSTIMER_BASE + 0x0004;
const uint SYSTIMER_UNIT0_VALUE_HI = SYSTIMER_BASE + 0x0040;
const uint SYSTIMER_UNIT0_VALUE_LO = SYSTIMER_BASE + 0x0044;
const uint TIMG_WDTFEED_OFFSET = 0x0060;

const uint SYSTEM_PERIP_CLK_EN0 = SYSTEM_BASE + 0x0010;
const uint SYSTEM_PERIP_RST_EN0 = SYSTEM_BASE + 0x0018;

const uint SYSTIMER_CLK_EN_BIT = 31;
const uint SYSTIMER_TIMER_UNIT0_WORK_EN_BIT = 30;
const uint SYSTIMER_TIMER_UNIT0_CORE0_STALL_EN_BIT = 28;
const uint SYSTIMER_TIMER_UNIT0_UPDATE_BIT = 30;
const uint SYSTIMER_TIMER_UNIT0_VALUE_VALID_BIT = 29;
const uint SYSTIMER_UNIT0_HI_MASK = 0x000F_FFFF;
const uint SYSTEM_SYSTIMER_CLK_EN_BIT = 30;
const uint SYSTEM_SYSTIMER_RST_BIT = 30;
const ulong ULONG_MAX_VALUE = 0xFFFF_FFFF_FFFF_FFFF;
const ulong MAX_MS_VALUE = 18_446_744_073_709_551;
const ulong MAX_SECONDS_VALUE = 18_446_744_073_709;

bool delay_timer_ready @local = false;

fn void reg_write(uint addr, uint value) {
    @volatile_store(*(uint*)addr, value);
}

fn uint reg_read(uint addr) {
    return @volatile_load(*(uint*)addr);
}

fn void feed_mwdt() {
    reg_write(TIMG0_BASE + TIMG_WDTFEED_OFFSET, 1);
}

fn ulong systimer_unit0_read_count() {
    reg_write(SYSTIMER_UNIT0_OP, 1u << SYSTIMER_TIMER_UNIT0_VALUE_VALID_BIT);
    reg_write(SYSTIMER_UNIT0_OP, 1u << SYSTIMER_TIMER_UNIT0_UPDATE_BIT);
    while ((reg_read(SYSTIMER_UNIT0_OP) & (1u << SYSTIMER_TIMER_UNIT0_VALUE_VALID_BIT)) == 0) {}

    uint lo = reg_read(SYSTIMER_UNIT0_VALUE_LO);
    uint hi = reg_read(SYSTIMER_UNIT0_VALUE_HI) & SYSTIMER_UNIT0_HI_MASK;
    return ((ulong)hi << 32) | lo;
}

fn void delay_timer_init() {
    reg_write(SYSTEM_PERIP_CLK_EN0, reg_read(SYSTEM_PERIP_CLK_EN0) | (1u << SYSTEM_SYSTIMER_CLK_EN_BIT));
    reg_write(SYSTEM_PERIP_RST_EN0, reg_read(SYSTEM_PERIP_RST_EN0) & ~(1u << SYSTEM_SYSTIMER_RST_BIT));

    uint cfg = reg_read(SYSTIMER_CONF);
    cfg |= 1u << SYSTIMER_CLK_EN_BIT;
    cfg |= 1u << SYSTIMER_TIMER_UNIT0_WORK_EN_BIT;
    cfg &= ~(1u << SYSTIMER_TIMER_UNIT0_CORE0_STALL_EN_BIT);
    reg_write(SYSTIMER_CONF, cfg);

    delay_timer_ready = true;
}

fn void delay_timer_ensure_init() {
    if (!delay_timer_ready) delay_timer_init();
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
    delay_timer_ensure_init();
    feed_mwdt();

    // ESP32-C3 systimer runs at 16 MHz in the reference implementation.
    return systimer_unit0_read_count() >> 4;
}

fn ClockInfo clock_info() {
    return { 1_000_000, 1, true, true };
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
    feed_mwdt();
    return (long)(now().ticks - deadline.ticks) >= 0;
}

fn void sleep(Duration duration) {
    if (duration_is_zero(duration)) return;
    sleep_until(deadline_after(duration));
}

fn void sleep_until(Instant deadline) {
    while (!has_elapsed(deadline)) {
        feed_mwdt();
    }
}
