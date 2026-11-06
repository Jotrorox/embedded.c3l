module std::core::embedded_intrinsics;

// The only library code under `std::`. c3c warns about every `$$` builtin used
// outside the standard library (once per macro expansion, and the warning can
// only be silenced on the command line, not from a template), so the three
// that the library needs are wrapped here. Everything else, including the
// public `@volatile_*`, `@compiler_barrier` and `@reg_*` macros, lives in
// embedded::core. Do not use this module directly.

macro @load(#x) => $$volatile_load(&#x);
macro @store(#x, value) => $$volatile_store(&#x, ($Typeof(#x))value);
macro mmio_load($Type, addr) => $$volatile_load(($Type*)(uptr)addr);
macro void mmio_store($Type, addr, value) => $$volatile_store(($Type*)(uptr)addr, ($Type)value);
macro void fence() => $$fence(6); // AtomicOrdering.SEQ_CONSISTENT
