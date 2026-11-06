module embedded::wdt @feat(MCU_ATMEGA328P);

import embedded::time;
import embedded::backends::avr::atmega328p::regs;



// 2048 cycles of the 128 kHz watchdog oscillator. Each prescaler step doubles it.
const ulong BASE_TIMEOUT_US = 16_000;
const char MAX_PRESCALER = 9;

bool reset_by_watchdog @local = false;

fn void reg_write(uint addr, char val) @local {
    @volatile_store(*(char*)(uptr)addr, val);
}

fn char reg_read(uint addr) @local {
    return @volatile_load(*(char*)(uptr)addr);
}

// Writes WDTCSR through the timed change sequence. The second store must land
// within four cycles of the first, so both are inlined volatile stores with
// interrupts off. Do not route them through a helper function.
// `value` is read back through a volatile load first: volatile accesses keep
// their order, so this forces it into a register before the first store and
// stops the compiler from sinking its computation between the two stores.
macro void timed_wdtcsr_write(char value) @local {
    char staged = value;
    char final_value = @volatile_load(staged);
    char old_sreg = reg_read(regs::SREG);
    asm("cli");
    asm("wdr");
    @volatile_store(*(char*)(uptr)regs::WDTCSR, regs::WDTCSR_WDCE | regs::WDTCSR_WDE);
    @volatile_store(*(char*)(uptr)regs::WDTCSR, final_value);
    reg_write(regs::SREG, old_sreg);
}

// Called once by the startup code, after .bss is cleared and before `start()`.
// The ATmega328P keeps the watchdog running with the shortest timeout after a
// watchdog reset, so this has to run early.
fn void boot() {
    reset_by_watchdog = (reg_read(regs::MCUSR) & regs::MCUSR_WDRF) != 0;
    disable();
}

fn Info info() {
    return {
        .min_timeout = time::us(BASE_TIMEOUT_US),
        .max_timeout = time::us(BASE_TIMEOUT_US << MAX_PRESCALER),
        .resolution = time::us(BASE_TIMEOUT_US),
    };
}

fn time::Duration? enable(time::Duration timeout) {
    if (timeout.micros == 0) return UNSUPPORTED_TIMEOUT~;

    char prescaler = 0;
    ulong period = BASE_TIMEOUT_US;
    while (period < timeout.micros) {
        if (prescaler == MAX_PRESCALER) return UNSUPPORTED_TIMEOUT~;
        prescaler++;
        period <<= 1;
    }

    char value = regs::WDTCSR_WDE | (prescaler & regs::WDTCSR_WDP_LOW_MASK);
    if (prescaler & 0x08) value |= regs::WDTCSR_WDP3;
    timed_wdtcsr_write(value);
    return time::us(period);
}

fn void disable() {
    // WDRF overrides WDE, so it has to be cleared before WDE can go low.
    reg_write(regs::MCUSR, (char)(reg_read(regs::MCUSR) & ~regs::MCUSR_WDRF));
    timed_wdtcsr_write(0);
}

fn void feed() {
    asm("wdr");
}

fn bool is_enabled() {
    return (reg_read(regs::WDTCSR) & regs::WDTCSR_WDE) != 0;
}

fn bool caused_reset() {
    return reset_by_watchdog;
}
