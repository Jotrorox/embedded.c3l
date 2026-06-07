module embedded::backends::esp32::esp32c3::startup @private;

const uint TIMG0_BASE = 0x6001_F000;
const uint TIMG1_BASE = 0x6002_0000;
const uint RTC_CNTL_BASE = 0x6000_8000;

const uint TIMG_WDTCONFIG0_OFFSET = 0x0048;
const uint TIMG_WDTFEED_OFFSET = 0x0060;
const uint TIMG_WDTWPROTECT_OFFSET = 0x0064;
const uint RTC_CNTL_WDTCONFIG0 = RTC_CNTL_BASE + 0x0090;
const uint RTC_CNTL_WDTWPROTECT = RTC_CNTL_BASE + 0x00A8;
const uint RTC_CNTL_SWD_CONF = RTC_CNTL_BASE + 0x00AC;
const uint RTC_CNTL_SWD_WPROTECT = RTC_CNTL_BASE + 0x00B0;

const uint TIMG_WDT_CONF_UPDATE_BIT = 13;
const uint TIMG_WDT_WKEY_VALUE = 0x50D8_3AA1;
const uint RTC_CNTL_SWD_AUTO_FEED_EN_BIT = 31;
const uint RTC_CNTL_SWD_WKEY_VALUE = 0x8F1D_312A;

extern fn void start();

fn void reg_write(uint addr, uint value) {
    @volatile_store(*(uint*)addr, value);
}

fn uint reg_read(uint addr) {
    return @volatile_load(*(uint*)addr);
}

fn void disable_mwdt(uint timer_group_base) {
    reg_write(timer_group_base + TIMG_WDTWPROTECT_OFFSET, TIMG_WDT_WKEY_VALUE);
    reg_write(timer_group_base + TIMG_WDTFEED_OFFSET, 1);
    reg_write(timer_group_base + TIMG_WDTCONFIG0_OFFSET, 0);
    reg_write(timer_group_base + TIMG_WDTCONFIG0_OFFSET, 1u << TIMG_WDT_CONF_UPDATE_BIT);
    reg_write(timer_group_base + TIMG_WDTWPROTECT_OFFSET, 0);
}

fn void feed_mwdt(uint timer_group_base) {
    reg_write(timer_group_base + TIMG_WDTFEED_OFFSET, 1);
}

fn void __init() @naked @noreturn @export("__init") @section(".init") {
    disable_mwdt(TIMG0_BASE);
    disable_mwdt(TIMG1_BASE);
    reg_write(RTC_CNTL_WDTWPROTECT, TIMG_WDT_WKEY_VALUE);
    reg_write(RTC_CNTL_WDTCONFIG0, 0);
    reg_write(RTC_CNTL_WDTWPROTECT, 0);
    reg_write(RTC_CNTL_SWD_WPROTECT, RTC_CNTL_SWD_WKEY_VALUE);
    reg_write(RTC_CNTL_SWD_CONF, reg_read(RTC_CNTL_SWD_CONF) | (1u << RTC_CNTL_SWD_AUTO_FEED_EN_BIT));
    reg_write(RTC_CNTL_SWD_WPROTECT, 0);
    feed_mwdt(TIMG0_BASE);

    start();
    while (true) {}
}
