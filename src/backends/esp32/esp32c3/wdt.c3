module embedded::wdt @feat(MCU_ESP32C3);

import embedded::core;
import embedded::time;
import embedded::backends::esp32::esp32c3::regs;

// 40 MHz crystal / 40 = 1 MHz, so one watchdog tick is 1 µs.
const uint TIMG_WDT_XTAL_PRESCALE = 40;
// Stage 0 timeout register width, in ticks.
const ulong TIMG_WDT_MAX_HOLD_TICKS = 0xFFFF_FFFF;

// Every MWDT register, including the feed register, is write-protected unless
// the key is in WDTWPROTECT. Writing anything else locks it again.
fn void mwdt_unlock(uint timer_group_base) @local {
    @reg_write(timer_group_base + regs::TIMG_WDTWPROTECT, regs::TIMG_WDT_WKEY);
}

fn void mwdt_lock(uint timer_group_base) @local {
    @reg_write(timer_group_base + regs::TIMG_WDTWPROTECT, 0);
}

// WDTCONFIG0..2 are only latched into the watchdog when CONF_UPDATE_EN is written.
fn void mwdt_write_config0(uint timer_group_base, uint value) @local {
    @reg_write(timer_group_base + regs::TIMG_WDTCONFIG0, value);
    @reg_write(timer_group_base + regs::TIMG_WDTCONFIG0, value | regs::TIMG_WDT_CONF_UPDATE_EN);
}

fn void disable_mwdt(uint timer_group_base) @local {
    mwdt_unlock(timer_group_base);
    @reg_write(timer_group_base + regs::TIMG_WDTFEED, 1);
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

    mwdt_unlock(regs::TIMG0_BASE);
    @reg_write(regs::TIMG0_BASE + regs::TIMG_WDTCONFIG1,
        (TIMG_WDT_XTAL_PRESCALE << regs::TIMG_WDT_CLK_PRESCALE_SHIFT) | regs::TIMG_WDT_DIVCNT_RST);
    @reg_write(regs::TIMG0_BASE + regs::TIMG_WDTCONFIG2, (uint)ticks);
    mwdt_write_config0(regs::TIMG0_BASE,
        regs::TIMG_WDT_EN
        | (regs::TIMG_WDT_STG_RESET_SYSTEM << regs::TIMG_WDT_STG0_SHIFT)
        | regs::TIMG_WDT_USE_XTAL
        | (regs::TIMG_WDT_RESET_LENGTH_3_2_US << regs::TIMG_WDT_CPU_RESET_LENGTH_SHIFT)
        | (regs::TIMG_WDT_RESET_LENGTH_3_2_US << regs::TIMG_WDT_SYS_RESET_LENGTH_SHIFT));
    @reg_write(regs::TIMG0_BASE + regs::TIMG_WDTFEED, 1);
    mwdt_lock(regs::TIMG0_BASE);
    return timeout;
}

// Disables the two timer-group watchdogs (MWDT0/1), the RTC watchdog and
// puts the super watchdog into auto-feed mode.
fn void disable() {
    disable_mwdt(regs::TIMG0_BASE);
    disable_mwdt(regs::TIMG1_BASE);

    @reg_write(regs::RTC_CNTL_WDTWPROTECT, regs::RTC_CNTL_WDT_WKEY);
    @reg_write(regs::RTC_CNTL_WDTCONFIG0, 0);
    @reg_write(regs::RTC_CNTL_WDTWPROTECT, 0);

    @reg_write(regs::RTC_CNTL_SWD_WPROTECT, regs::RTC_CNTL_SWD_WKEY);
    @reg_write(regs::RTC_CNTL_SWD_CONF, @reg_read(regs::RTC_CNTL_SWD_CONF) | regs::RTC_CNTL_SWD_AUTO_FEED_EN);
    @reg_write(regs::RTC_CNTL_SWD_WPROTECT, 0);
}

fn void feed() {
    mwdt_unlock(regs::TIMG0_BASE);
    @reg_write(regs::TIMG0_BASE + regs::TIMG_WDTFEED, 1);
    mwdt_lock(regs::TIMG0_BASE);
}

fn bool is_enabled() {
    return (@reg_read(regs::TIMG0_BASE + regs::TIMG_WDTCONFIG0) & regs::TIMG_WDT_EN) != 0;
}

fn bool caused_reset() {
    switch (@reg_read(regs::RTC_CNTL_RESET_STATE) & regs::RTC_CNTL_RESET_CAUSE_MASK) {
        case regs::RESET_TG0WDT_SYS:
        case regs::RESET_TG1WDT_SYS:
        case regs::RESET_RTCWDT_SYS:
        case regs::RESET_TG0WDT_CPU:
        case regs::RESET_RTCWDT_CPU:
        case regs::RESET_RTCWDT_RTC:
        case regs::RESET_TG1WDT_CPU:
        case regs::RESET_SUPER_WDT:
            return true;
        default:
            return false;
    }
}
