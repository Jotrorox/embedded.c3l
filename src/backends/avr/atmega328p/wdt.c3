module embedded::wdt;

import embedded::time;

const uint MCUSR  = 0x54;
const uint WDTCSR = 0x60;
const uint SREG   = 0x5F;

const char MCUSR_WDRF  = 1 << 3;
const char WDTCSR_WDE  = 1 << 3;
const char WDTCSR_WDCE = 1 << 4;
const char WDTCSR_WDP3 = 1 << 5;
const char WDTCSR_WDP_LOW_MASK = 0x07;

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
    char old_sreg = reg_read(SREG);
    asm("cli");
    asm("wdr");
    @volatile_store(*(char*)(uptr)WDTCSR, WDTCSR_WDCE | WDTCSR_WDE);
    @volatile_store(*(char*)(uptr)WDTCSR, final_value);
    reg_write(SREG, old_sreg);
}

// Called once by the startup code, after .bss is cleared and before `start()`.
// The ATmega328P keeps the watchdog running with the shortest timeout after a
// watchdog reset, so this has to run early.
fn void boot() {
    reset_by_watchdog = (reg_read(MCUSR) & MCUSR_WDRF) != 0;
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

    char value = WDTCSR_WDE | (prescaler & WDTCSR_WDP_LOW_MASK);
    if (prescaler & 0x08) value |= WDTCSR_WDP3;
    timed_wdtcsr_write(value);
    return time::us(period);
}

fn void disable() {
    // WDRF overrides WDE, so it has to be cleared before WDE can go low.
    reg_write(MCUSR, (char)(reg_read(MCUSR) & ~MCUSR_WDRF));
    timed_wdtcsr_write(0);
}

fn void feed() {
    asm("wdr");
}

fn bool is_enabled() {
    return (reg_read(WDTCSR) & WDTCSR_WDE) != 0;
}

fn bool caused_reset() {
    return reset_by_watchdog;
}
