module embedded::wdt;

import embedded::time;

const uint TIMG0_BASE = 0x6001_F000;
const uint TIMG1_BASE = 0x6002_0000;
const uint RTC_CNTL_BASE = 0x6000_8000;

const uint TIMG_WDTCONFIG0_OFFSET = 0x0048;
const uint TIMG_WDTCONFIG1_OFFSET = 0x004C;
const uint TIMG_WDTCONFIG2_OFFSET = 0x0050;
const uint TIMG_WDTFEED_OFFSET = 0x0060;
const uint TIMG_WDTWPROTECT_OFFSET = 0x0064;
const uint RTC_CNTL_RESET_STATE = RTC_CNTL_BASE + 0x0038;
const uint RTC_CNTL_WDTCONFIG0 = RTC_CNTL_BASE + 0x0090;
const uint RTC_CNTL_WDTWPROTECT = RTC_CNTL_BASE + 0x00A8;
const uint RTC_CNTL_SWD_CONF = RTC_CNTL_BASE + 0x00AC;
const uint RTC_CNTL_SWD_WPROTECT = RTC_CNTL_BASE + 0x00B0;

// TIMG_WDTCONFIG0 fields.
const uint TIMG_WDT_EN_BIT = 31;
const uint TIMG_WDT_STG0_SHIFT = 29;
const uint TIMG_WDT_CONF_UPDATE_EN_BIT = 22;
const uint TIMG_WDT_USE_XTAL_BIT = 21;
const uint TIMG_WDT_CPU_RESET_LENGTH_SHIFT = 18;
const uint TIMG_WDT_SYS_RESET_LENGTH_SHIFT = 15;
// TIMG_WDTCONFIG1 fields.
const uint TIMG_WDT_CLK_PRESCALE_SHIFT = 16;
const uint TIMG_WDT_DIVCNT_RST_BIT = 0;

const uint TIMG_WDT_STAGE_RESET_SYSTEM = 3;
const uint TIMG_WDT_RESET_LENGTH_3_2_US = 7;
// 40 MHz crystal / 40 = 1 MHz, so one watchdog tick is 1 µs.
const uint TIMG_WDT_XTAL_PRESCALE = 40;
const ulong TIMG_WDT_MAX_HOLD_TICKS = 0xFFFF_FFFF;

const uint TIMG_WDT_WKEY_VALUE = 0x50D8_3AA1;
const uint RTC_CNTL_SWD_AUTO_FEED_EN_BIT = 31;
const uint RTC_CNTL_SWD_WKEY_VALUE = 0x8F1D_312A;

const uint RTC_CNTL_RESET_CAUSE_MASK = 0x3F;
// Watchdog reset causes from esp-idf's RESET_REASON enum (esp32c3/rom/rtc.h).
const uint RESET_TG0WDT_SYS = 7;
const uint RESET_TG1WDT_SYS = 8;
const uint RESET_RTCWDT_SYS = 9;
const uint RESET_TG0WDT_CPU = 11;
const uint RESET_RTCWDT_CPU = 13;
const uint RESET_RTCWDT_RTC = 16;
const uint RESET_TG1WDT_CPU = 17;
const uint RESET_SUPER_WDT = 18;

fn void reg_write(uint addr, uint value) @local {
    @volatile_store(*(uint*)addr, value);
}

fn uint reg_read(uint addr) @local {
    return @volatile_load(*(uint*)addr);
}

// Every MWDT register, including the feed register, is write-protected unless
// the key is in WDTWPROTECT. Writing anything else locks it again.
fn void mwdt_unlock(uint timer_group_base) @local {
    reg_write(timer_group_base + TIMG_WDTWPROTECT_OFFSET, TIMG_WDT_WKEY_VALUE);
}

fn void mwdt_lock(uint timer_group_base) @local {
    reg_write(timer_group_base + TIMG_WDTWPROTECT_OFFSET, 0);
}

// WDTCONFIG0..2 are only latched into the watchdog when CONF_UPDATE_EN is written.
fn void mwdt_write_config0(uint timer_group_base, uint value) @local {
    reg_write(timer_group_base + TIMG_WDTCONFIG0_OFFSET, value);
    reg_write(timer_group_base + TIMG_WDTCONFIG0_OFFSET, value | (1u << TIMG_WDT_CONF_UPDATE_EN_BIT));
}

fn void disable_mwdt(uint timer_group_base) @local {
    mwdt_unlock(timer_group_base);
    reg_write(timer_group_base + TIMG_WDTFEED_OFFSET, 1);
    mwdt_write_config0(timer_group_base, 0);
    mwdt_lock(timer_group_base);
}

// Called once by the startup code before `start()`.
fn void boot() {
    disable();
}

fn Info info() {
    return {
        .min_timeout = time::us(1),
        .max_timeout = time::us(TIMG_WDT_MAX_HOLD_TICKS),
        .resolution = time::us(1),
    };
}

fn time::Duration? enable(time::Duration timeout) {
    ulong ticks = timeout.micros;
    if (ticks == 0 || ticks > TIMG_WDT_MAX_HOLD_TICKS) return UNSUPPORTED_TIMEOUT~;

    mwdt_unlock(TIMG0_BASE);
    reg_write(TIMG0_BASE + TIMG_WDTCONFIG1_OFFSET,
        (TIMG_WDT_XTAL_PRESCALE << TIMG_WDT_CLK_PRESCALE_SHIFT) | (1u << TIMG_WDT_DIVCNT_RST_BIT));
    reg_write(TIMG0_BASE + TIMG_WDTCONFIG2_OFFSET, (uint)ticks);
    mwdt_write_config0(TIMG0_BASE,
        (1u << TIMG_WDT_EN_BIT)
        | (TIMG_WDT_STAGE_RESET_SYSTEM << TIMG_WDT_STG0_SHIFT)
        | (1u << TIMG_WDT_USE_XTAL_BIT)
        | (TIMG_WDT_RESET_LENGTH_3_2_US << TIMG_WDT_CPU_RESET_LENGTH_SHIFT)
        | (TIMG_WDT_RESET_LENGTH_3_2_US << TIMG_WDT_SYS_RESET_LENGTH_SHIFT));
    reg_write(TIMG0_BASE + TIMG_WDTFEED_OFFSET, 1);
    mwdt_lock(TIMG0_BASE);
    return timeout;
}

// Disables the two timer-group watchdogs (MWDT0/1), the RTC watchdog and
// puts the super watchdog into auto-feed mode.
fn void disable() {
    disable_mwdt(TIMG0_BASE);
    disable_mwdt(TIMG1_BASE);

    reg_write(RTC_CNTL_WDTWPROTECT, TIMG_WDT_WKEY_VALUE);
    reg_write(RTC_CNTL_WDTCONFIG0, 0);
    reg_write(RTC_CNTL_WDTWPROTECT, 0);

    reg_write(RTC_CNTL_SWD_WPROTECT, RTC_CNTL_SWD_WKEY_VALUE);
    reg_write(RTC_CNTL_SWD_CONF, reg_read(RTC_CNTL_SWD_CONF) | (1u << RTC_CNTL_SWD_AUTO_FEED_EN_BIT));
    reg_write(RTC_CNTL_SWD_WPROTECT, 0);
}

fn void feed() {
    mwdt_unlock(TIMG0_BASE);
    reg_write(TIMG0_BASE + TIMG_WDTFEED_OFFSET, 1);
    mwdt_lock(TIMG0_BASE);
}

fn bool is_enabled() {
    return (reg_read(TIMG0_BASE + TIMG_WDTCONFIG0_OFFSET) & (1u << TIMG_WDT_EN_BIT)) != 0;
}

fn bool caused_reset() {
    switch (reg_read(RTC_CNTL_RESET_STATE) & RTC_CNTL_RESET_CAUSE_MASK) {
        case RESET_TG0WDT_SYS:
        case RESET_TG1WDT_SYS:
        case RESET_RTCWDT_SYS:
        case RESET_TG0WDT_CPU:
        case RESET_RTCWDT_CPU:
        case RESET_RTCWDT_RTC:
        case RESET_TG1WDT_CPU:
        case RESET_SUPER_WDT:
            return true;
        default:
            return false;
    }
}
