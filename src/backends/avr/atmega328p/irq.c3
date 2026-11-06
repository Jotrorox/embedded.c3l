module embedded::irq;

import embedded::backends::avr::atmega328p::soc;
import embedded::backends::avr::atmega328p::regs;

// The saved status register. Only its I bit matters to `restore()`.
typedef State = char;

// ATmega328P vector numbers (datasheet table 12-6). The handler for vector N
// is the symbol "__vector_N"; vector 0 is reset.
constdef Vector : inline char {
    INT0         = 1,
    INT1         = 2,
    PCINT0       = 3,
    PCINT1       = 4,
    PCINT2       = 5,
    WDT          = 6,
    TIMER2_COMPA = 7,
    TIMER2_COMPB = 8,
    TIMER2_OVF   = 9,
    TIMER1_CAPT  = 10,
    TIMER1_COMPA = 11,
    TIMER1_COMPB = 12,
    TIMER1_OVF   = 13,
    TIMER0_COMPA = 14,
    TIMER0_COMPB = 15,
    TIMER0_OVF   = 16,
    SPI_STC      = 17,
    USART_RX     = 18,
    USART_UDRE   = 19,
    USART_TX     = 20,
    ADC          = 21,
    EE_READY     = 22,
    ANALOG_COMP  = 23,
    TWI          = 24,
    SPM_READY    = 25,
}

fn void enable() @inline
{
    @compiler_barrier();
    asm("sei");
}

fn void disable() @inline
{
    asm("cli");
    @compiler_barrier();
}

fn bool is_enabled() @inline => (soc::read8(regs::SREG) & regs::SREG_I) != 0;

fn State save_and_disable() @inline
{
    State state = (State)soc::read8(regs::SREG);
    asm("cli");
    @compiler_barrier();
    return state;
}

fn void restore(State state) @inline
{
    @compiler_barrier();
    soc::write8(regs::SREG, (char)state);
}

// Body of an interrupt vector. Saves the call-clobbered registers, calls the
// exported function named `$handler` like a normal function, and returns with
// `reti`. Use it as the only statement of a `@naked` function exported as
// "__vector_N":
//
//     fn void on_compare() @export("on_compare") { ... }
//     fn void timer2_compa() @export("__vector_7") @naked { irq::@isr("on_compare"); }
//
// The vector itself is five instructions: it saves Z, loads the handler's
// address into Z and jumps to the shared `__irq_call_z` routine. The handler
// is an ordinary C3 function, so the compiler saves any call-saved registers
// it uses.
macro void @isr(String $handler)
{
    asm("push r30");
    asm("push r31");
    asm("ldi r30, pm_lo8(" +++ $handler +++ ")");
    asm("ldi r31, pm_hi8(" +++ $handler +++ ")");
    asm("rjmp __irq_call_z"); // in range: the linker script keeps it near the vectors
}

// Shared tail of every `@isr` vector. Z (r30:r31) is already saved and holds
// the handler's word address. Saves what avr-gcc's ABI lets a function clobber
// (r0, SREG, r1, r18-r27), sets r1 to zero as the ABI requires, calls the
// handler and unwinds.
fn void __irq_call_z() @naked @nostrip @export("__irq_call_z")
{
    asm("push r0");
    asm("in r0, 0x3f");                 // SREG
    asm("push r0");
    asm("push r1");
    asm("eor r1, r1");
    asm("push r18");
    asm("push r19");
    asm("push r20");
    asm("push r21");
    asm("push r22");
    asm("push r23");
    asm("push r24");
    asm("push r25");
    asm("push r26");
    asm("push r27");
    asm("icall");
    asm("pop r27");
    asm("pop r26");
    asm("pop r25");
    asm("pop r24");
    asm("pop r23");
    asm("pop r22");
    asm("pop r21");
    asm("pop r20");
    asm("pop r19");
    asm("pop r18");
    asm("pop r1");
    asm("pop r0");
    asm("out 0x3f, r0");                // SREG
    asm("pop r0");
    asm("pop r31");
    asm("pop r30");
    asm("reti");
}
