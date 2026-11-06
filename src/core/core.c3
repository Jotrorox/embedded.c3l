module embedded::core;

import std::core::embedded_intrinsics;

// Low-level helpers shared by the backends. The macros are `@builtin`, but
// outside `std::` that only drops the module prefix: a file that uses them
// still needs `import embedded::core;`. The `$$` builtins underneath are in
// intrinsics.c3, see the note there.

macro @volatile_load(#x) @builtin
{
    return embedded_intrinsics::@load(#x);
}

macro @volatile_store(#x, value) @builtin
{
    return embedded_intrinsics::@store(#x, value);
}

// Compiler memory barrier: no instruction on AVR, one `fence` on RISC-V; the
// optimiser may not move memory accesses across it. Inline asm strings carry
// no memory clobber, so `asm("cli")` alone does not stop the compiler from
// hoisting a store out of a critical section. Put this next to such asm.
macro void @compiler_barrier() @builtin
{
    embedded_intrinsics::fence();
}

// ---------------------------------------------------------------------------
// Memory-mapped registers.
//
// `addr` is the register's address (any integer, usually a `regs::`
// constant). Every access is volatile and has exactly the width of `$Type`,
// which defaults to the MCU's register width: 8 bits on AVR, 32 bits on the
// ESP32-C3. Pass the type for other widths, e.g. `@reg_read(addr, ushort)`.
// Values and masks are converted to `$Type`, so a wider value is truncated.
//
// The read-modify-write helpers are not atomic. Keep interrupts off around
// them when an ISR writes the same register, or use the hardware's
// set/clear registers (W1TS/W1TC on the ESP32-C3, PINx toggling on AVR).
//
// AVR 16-bit timer registers need a fixed byte order, see `soc::write16`.

alias Reg @feat(BACKEND_AVR) = char;
alias Reg @feat(!BACKEND_AVR) = uint;

macro @reg_read(addr, $Type = Reg) @builtin
{
    return embedded_intrinsics::mmio_load($Type, addr);
}

macro void @reg_write(addr, value, $Type = Reg) @builtin
{
    embedded_intrinsics::mmio_store($Type, addr, value);
}

macro void @reg_set_bits(addr, mask, $Type = Reg) @builtin
{
    @reg_write(addr, @reg_read(addr, $Type) | ($Type)mask, $Type);
}

macro void @reg_clear_bits(addr, mask, $Type = Reg) @builtin
{
    @reg_write(addr, @reg_read(addr, $Type) & ($Type)~($Type)mask, $Type);
}

// Replaces the bits selected by `mask` with the same bits of `value`, which
// must already be shifted into place. Other bits keep their value.
macro void @reg_update(addr, mask, value, $Type = Reg) @builtin
{
    @reg_write(addr, (@reg_read(addr, $Type) & ($Type)~($Type)mask) | (($Type)value & ($Type)mask), $Type);
}
