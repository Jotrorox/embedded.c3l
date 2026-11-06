module embedded::irq;

import embedded::backends::esp32::esp32c3::soc;

// The saved mstatus CSR. Only its MIE bit matters to `restore()`.
typedef State = uint;

// Peripheral interrupt sources (ESP-IDF soc/esp32c3/include/soc/interrupts.h).
// Sources reserved for the radio, flash cache and memory protection are left
// out.
constdef Source : inline char {
    UHCI0            = 15,
    GPIO             = 16,
    SPI2             = 19,
    I2S1             = 20,
    UART0            = 21,
    UART1            = 22,
    LEDC             = 23,
    TWAI             = 25,
    USB_SERIAL_JTAG  = 26,
    RTC_CORE         = 27,
    RMT              = 28,
    I2C_EXT0         = 29,
    TIMER1           = 30,
    TIMER2           = 31,
    TG0_T0           = 32,
    TG0_WDT          = 33,
    TG1_T0           = 34,
    TG1_WDT          = 35,
    SYSTIMER_TARGET0 = 37,
    SYSTIMER_TARGET1 = 38,
    SYSTIMER_TARGET2 = 39,
    APB_ADC          = 43,
    DMA_CH0          = 44,
    DMA_CH1          = 45,
    DMA_CH2          = 46,
    RSA              = 47,
    AES              = 48,
    SHA              = 49,
    FROM_CPU0        = 50,
    FROM_CPU1        = 51,
    FROM_CPU2        = 52,
    FROM_CPU3        = 53,
    ASSIST_DEBUG     = 54,
}

const uint SOURCE_COUNT = 62;
const uint LINE_COUNT = 32; // CPU interrupt lines; line 0 means "not routed"

// Interrupt matrix (INTERRUPT_CORE0). Each source has a map register holding
// the CPU line it is routed to.
const uint INTC_BASE = 0x600C_2000;
const uint INTC_CPU_INT_ENABLE = INTC_BASE + 0x104;
const uint INTC_CPU_INT_TYPE   = INTC_BASE + 0x108;
const uint INTC_CPU_INT_CLEAR  = INTC_BASE + 0x10C;
const uint INTC_CPU_INT_PRI_0  = INTC_BASE + 0x114;
const uint INTC_CPU_INT_THRESH = INTC_BASE + 0x194;

const uint MSTATUS_MIE = 1u << 3;
const uint MCAUSE_INTERRUPT = 1u << 31;

Handler[LINE_COUNT] line_handlers @local;

fn uint map_reg(uint source) @local => INTC_BASE + source * 4;

// mstatus is a CSR, which needs register operands that C3 string asm cannot
// express, so these are tiny naked functions using the calling convention:
// the argument and the result are in a0.
fn uint csr_clear_mie() @naked @noinline @export("embedded_esp32_csr_clear_mie") {
    asm("csrrci a0, mstatus, 8");
    asm("ret");
}

fn void csr_restore_mie(uint saved) @naked @noinline @export("embedded_esp32_csr_restore_mie") {
    asm("andi a0, a0, 8");
    asm("csrs mstatus, a0");
    asm("ret");
}

fn uint csr_read_mstatus() @naked @noinline @export("embedded_esp32_csr_read_mstatus") {
    asm("csrr a0, mstatus");
    asm("ret");
}

fn void enable() {
    @compiler_barrier();
    asm("csrsi mstatus, 8");
}

fn void disable() {
    asm("csrci mstatus, 8");
    @compiler_barrier();
}

fn bool is_enabled() => (csr_read_mstatus() & MSTATUS_MIE) != 0;

fn State save_and_disable() {
    State state = (State)csr_clear_mie();
    @compiler_barrier();
    return state;
}

fn void restore(State state) {
    @compiler_barrier();
    csr_restore_mie((uint)state);
}

fn void? attach(Source source, Handler handler, char priority = 1) {
    if ((uint)source >= SOURCE_COUNT) return INVALID_SOURCE~;
    if (priority < 1 || priority > 15) return INVALID_PRIORITY~;

    State state = save_and_disable();
    defer restore(state);

    if (soc::read(map_reg(source)) != 0) return ALREADY_ATTACHED~;
    uint line = 0;
    for (uint candidate = 1; candidate < LINE_COUNT; candidate++) {
        if (!line_handlers[candidate]) {
            line = candidate;
            break;
        }
    }
    if (line == 0) return NO_FREE_LINE~;

    line_handlers[line] = handler;
    soc::write(INTC_CPU_INT_PRI_0 + line * 4, priority);
    soc::clear_bits(INTC_CPU_INT_TYPE, 1u << line); // level-triggered
    soc::write(map_reg(source), line);
    soc::set_bits(INTC_CPU_INT_ENABLE, 1u << line);
}

fn void detach(Source source) {
    if ((uint)source >= SOURCE_COUNT) return;
    State state = save_and_disable();
    defer restore(state);

    uint line = soc::read(map_reg(source)) & 0x1F;
    if (line == 0) return;
    soc::clear_bits(INTC_CPU_INT_ENABLE, 1u << line);
    soc::write(map_reg(source), 0);
    line_handlers[line] = null;
}

// Called once by the start-up code, before interrupts are enabled: unroutes
// every source (the boot ROM may have left some connected), disables every
// line and lets priority 1 and above through.
fn void init() {
    soc::write(INTC_CPU_INT_ENABLE, 0);
    for (uint source = 0; source < SOURCE_COUNT; source++) soc::write(map_reg(source), 0);
    soc::write(INTC_CPU_INT_CLEAR, 0xFFFF_FFFF);
    soc::write(INTC_CPU_INT_CLEAR, 0);
    soc::write(INTC_CPU_INT_THRESH, 1);
}

// Called for a CPU exception (illegal instruction, misaligned or faulting
// access, ecall, ebreak). Weak: firmware can define
// `embedded_esp32_exception` to report the fault. The default halts, because
// returning would re-execute the faulting instruction.
fn void exception(uint mcause, uint mepc, uint mtval) @weak @export("embedded_esp32_exception") {
    while (true) asm("wfi");
}

// Common trap dispatcher, called by `trap_entry` with interrupts disabled.
fn void dispatch(uint mcause, uint mepc, uint mtval) @export("embedded_esp32_trap") {
    if ((mcause & MCAUSE_INTERRUPT) == 0) {
        exception(mcause, mepc, mtval);
        return;
    }
    uint line = mcause & 0x1F;
    Handler handler = line_handlers[line];
    if (handler) {
        handler();
    } else {
        // Nothing to call, and a level interrupt would fire again at once.
        soc::clear_bits(INTC_CPU_INT_ENABLE, 1u << line);
    }
}

// Saves the registers a C function may clobber (ra, t0-t6, a0-a7), calls the
// dispatcher with mcause/mepc/mtval and returns with mret. Nested interrupts
// are not supported: the CPU clears MIE on entry and mret restores it.
fn void trap_entry() @naked @export("embedded_esp32_trap_entry") {
    asm("addi sp, sp, -64");
    asm("sw ra, 0(sp)");
    asm("sw t0, 4(sp)");
    asm("sw t1, 8(sp)");
    asm("sw t2, 12(sp)");
    asm("sw a0, 16(sp)");
    asm("sw a1, 20(sp)");
    asm("sw a2, 24(sp)");
    asm("sw a3, 28(sp)");
    asm("sw a4, 32(sp)");
    asm("sw a5, 36(sp)");
    asm("sw a6, 40(sp)");
    asm("sw a7, 44(sp)");
    asm("sw t3, 48(sp)");
    asm("sw t4, 52(sp)");
    asm("sw t5, 56(sp)");
    asm("sw t6, 60(sp)");
    asm("csrr a0, mcause");
    asm("csrr a1, mepc");
    asm("csrr a2, mtval");
    asm("call embedded_esp32_trap");
    asm("lw ra, 0(sp)");
    asm("lw t0, 4(sp)");
    asm("lw t1, 8(sp)");
    asm("lw t2, 12(sp)");
    asm("lw a0, 16(sp)");
    asm("lw a1, 20(sp)");
    asm("lw a2, 24(sp)");
    asm("lw a3, 28(sp)");
    asm("lw a4, 32(sp)");
    asm("lw a5, 36(sp)");
    asm("lw a6, 40(sp)");
    asm("lw a7, 44(sp)");
    asm("lw t3, 48(sp)");
    asm("lw t4, 52(sp)");
    asm("lw t5, 56(sp)");
    asm("lw t6, 60(sp)");
    asm("addi sp, sp, 64");
    asm("mret");
}

// Vectored mtvec table: entry 0 is taken for exceptions, entry N for CPU
// interrupt line N. The ESP32-C3 only supports vectored mode, which needs a
// 256-byte aligned table of 4-byte jumps, so compressed instructions are
// switched off here.
fn void vectors() @naked @nostrip @align(256) @export("embedded_esp32_vectors") @section(".text.vectors") {
    // Each asm statement is assembled on its own, so every entry carries its
    // own push/pop of the assembler options.
    $for var $i = 0; $i < 32; $i++:
        asm(".option push\n.option norvc\nj embedded_esp32_trap_entry\n.option pop");
    $endfor
}
