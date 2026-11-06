module std::core::embedded;

macro @volatile_load(#x) @builtin
{
    return $$volatile_load(&#x);
}

macro @volatile_store(#x, value) @builtin
{
    return $$volatile_store(&#x, ($Typeof(#x))value);
}

// Compiler memory barrier: no instruction on AVR, one `fence` on RISC-V; the
// optimiser may not move memory accesses across it. Inline asm strings carry
// no memory clobber, so `asm("cli")` alone does not stop the compiler from
// hoisting a store out of a critical section. Put this next to such asm.
macro void @compiler_barrier() @builtin
{
    $$fence(6); // AtomicOrdering.SEQ_CONSISTENT
}
