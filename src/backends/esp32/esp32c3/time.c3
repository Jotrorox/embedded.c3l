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

fn ulong micros() {
    delay_timer_ensure_init();
    feed_mwdt();

    // ESP32-C3 systimer runs at 16 MHz in the reference implementation.
    return systimer_unit0_read_count() >> 4;
}

fn ulong millis() {
    return micros() / 1000;
}

fn void delay_us(uint us) {
    delay_timer_ensure_init();
    feed_mwdt();

    ulong start = systimer_unit0_read_count();
    ulong target = (ulong)us << 4;
    while (systimer_unit0_read_count() - start < target) {
        feed_mwdt();
    }
}

fn void delay_ms(uint ms) {
    delay_timer_ensure_init();
    feed_mwdt();

    while (ms > 0) {
        feed_mwdt();
        uint chunk = ms > 100 ? 100 : ms;
        ulong start = systimer_unit0_read_count();
        uint target = chunk * 16000u;
        while (systimer_unit0_read_count() - start < (ulong)target) {
            feed_mwdt();
        }
        ms -= chunk;
    }
}
