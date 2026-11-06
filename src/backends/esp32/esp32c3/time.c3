module embedded::time @feat(MCU_ESP32C3);

import embedded::core;
import embedded::backends::esp32::esp32c3::regs;

bool delay_timer_ready @local = false;

fn ulong systimer_unit0_read_count() {
    @reg_write(regs::SYSTIMER_UNIT0_OP, regs::SYSTIMER_UNIT0_VALUE_VALID);
    @reg_write(regs::SYSTIMER_UNIT0_OP, regs::SYSTIMER_UNIT0_UPDATE);
    while ((@reg_read(regs::SYSTIMER_UNIT0_OP) & regs::SYSTIMER_UNIT0_VALUE_VALID) == 0) {}

    uint lo = @reg_read(regs::SYSTIMER_UNIT0_VALUE_LO);
    uint hi = @reg_read(regs::SYSTIMER_UNIT0_VALUE_HI) & regs::SYSTIMER_UNIT0_VALUE_HI_MASK;
    return ((ulong)hi << 32) | lo;
}

fn void delay_timer_init() {
    @reg_write(regs::SYSTEM_PERIP_CLK_EN0, @reg_read(regs::SYSTEM_PERIP_CLK_EN0) | regs::PERIP_SYSTIMER);
    @reg_write(regs::SYSTEM_PERIP_RST_EN0, @reg_read(regs::SYSTEM_PERIP_RST_EN0) & ~regs::PERIP_SYSTIMER);

    uint cfg = @reg_read(regs::SYSTIMER_CONF);
    cfg |= regs::SYSTIMER_CONF_CLK_EN;
    cfg |= regs::SYSTIMER_CONF_UNIT0_WORK_EN;
    cfg &= ~regs::SYSTIMER_CONF_UNIT0_CORE0_STALL_EN;
    @reg_write(regs::SYSTIMER_CONF, cfg);

    delay_timer_ready = true;
}

fn void delay_timer_ensure_init() {
    if (!delay_timer_ready) delay_timer_init();
}

fn ulong read_micros() {
    delay_timer_ensure_init();

    // ESP32-C3 systimer runs at 16 MHz in the reference implementation.
    return systimer_unit0_read_count() >> 4;
}

fn ClockInfo clock_info() {
    return { 1_000_000, 1, true, true };
}

// Duration arithmetic, deadlines and `sleep()` are in src/api/time_common.c3.
fn Instant now() {
    return { (Ticks)read_micros() };
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
