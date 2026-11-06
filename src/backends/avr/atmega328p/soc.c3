module embedded::backends::avr::atmega328p::soc @feat(MCU_ATMEGA328P);

import embedded::core;

// Shared ATmega328P definitions for the backend modules. Not part of the
// public API.

// The Uno runs from a 16 MHz crystal.
const uint CPU_HZ = 16_000_000;

// Register addresses and bit names are in regs.c3. 8-bit registers are
// accessed with the `@reg_*` macros from embedded::core.

// 16-bit timer registers must be written high byte first and read low byte
// first: the high byte goes through a shared TEMP register (datasheet 15.3).
// Callers must keep interrupts off around these if an ISR also touches a
// 16-bit timer register.
macro void write16(uint addr, ushort value)
{
    @reg_write(addr + 1, value >> 8);
    @reg_write(addr, value);
}

macro ushort read16(uint addr)
{
    char low = @reg_read(addr);
    return (ushort)@reg_read(addr + 1) << 8 | low;
}
