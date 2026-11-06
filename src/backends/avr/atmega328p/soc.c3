module embedded::backends::avr::atmega328p::soc @feat(MCU_ATMEGA328P);

// Shared ATmega328P definitions for the backend modules. Not part of the
// public API.

// The Uno runs from a 16 MHz crystal.
const uint CPU_HZ = 16_000_000;

// Register addresses and bit names are in regs.c3.

macro char read8(uint addr) => @volatile_load(*(char*)(uptr)addr);
macro void write8(uint addr, char value) => @volatile_store(*(char*)(uptr)addr, value);
macro void set8(uint addr, char mask) => write8(addr, read8(addr) | mask);
macro void clear8(uint addr, char mask) => write8(addr, read8(addr) & (char)~mask);

// 16-bit timer registers must be written high byte first and read low byte
// first: the high byte goes through a shared TEMP register (datasheet 15.3).
// Callers must keep interrupts off around these if an ISR also touches a
// 16-bit timer register.
macro void write16(uint addr, ushort value)
{
    write8(addr + 1, (char)(value >> 8));
    write8(addr, (char)value);
}

macro ushort read16(uint addr)
{
    char low = read8(addr);
    return (ushort)read8(addr + 1) << 8 | low;
}
