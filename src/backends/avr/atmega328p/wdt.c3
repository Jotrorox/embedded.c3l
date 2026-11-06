module embedded::wdt;

const uint MCUSR  = 0x54;
const uint WDTCSR = 0x60;
const uint SREG   = 0x5F;

const char MCUSR_WDRF  = 1 << 3;
const char WDTCSR_WDE  = 1 << 3;
const char WDTCSR_WDCE = 1 << 4;

fn void reg_write(uint addr, char val) {
    @volatile_store(*(char*)(uptr)addr, val);
}

fn char reg_read(uint addr) {
    return @volatile_load(*(char*)(uptr)addr);
}

// Turns the watchdog timer off. After a watchdog reset the ATmega328P keeps the
// watchdog running with the shortest timeout, so this must run early in startup.
fn void disable() {
    char old_sreg = reg_read(SREG);
    asm("cli");
    asm("wdr");
    reg_write(MCUSR, (char)(reg_read(MCUSR) & ~MCUSR_WDRF));
    // Timed sequence: the second write must land within four cycles of the first.
    reg_write(WDTCSR, (char)(reg_read(WDTCSR) | WDTCSR_WDCE | WDTCSR_WDE));
    reg_write(WDTCSR, 0);
    reg_write(SREG, old_sreg);
}

fn void feed() {
    asm("wdr");
}
