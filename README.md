# embedded.c3l

`embedded.c3l` is a source-selected embedded HAL for C3.

Board templates select the active board and MCU backend. Application code should
not import AVR, ESP32-C3, or other backend-specific modules directly.

## Requirements

- `c3c` **0.8.6 or newer**. At the time of writing 0.8.6 is only available as a
  pre-release (nightly); the library uses template keys and manifest fields that
  0.8.5 does not support. CI builds every example against the nightly compiler
  (required) and the latest stable release (informational).

## Supported Templates

| Board | Release | Debug |
|---|---|---|
| Arduino Uno | `embedded/arduino_uno` | `embedded/arduino_uno_debug` |
| ESP32-C3 SuperMini | `embedded/esp32c3_supermini` | `embedded/esp32c3_supermini_debug` |

The release templates build with `Oz` and no runtime checks. The debug
templates build with `O1`, `safe` (contracts, bounds and null checks),
panic messages and line tables, and name `embedded::panic::handler` as the
`panicfn`: a failed check prints its message and location on the board's
console, then the watchdog resets the chip while the LED flashes. A target can
override any single key of its template, for example
`{ "template": "embedded/arduino_uno_debug", "opt": "Os" }`.

`trap-on-wrap` is not in the debug templates. It applies to the library too,
whose runtime helpers and clocks wrap on purpose, and c3c has no way to allow
wrapping for single expressions.

The checks cost space, on the Uno mostly SRAM because AVR keeps the panic
texts there: `blink` grows from 2.2 KB flash and 114 B SRAM to 10.7 KB and
842 B, `professional` uses 1.4 KB of the 2 KB SRAM. The panic handler is
described in `src/api/panic.c3`, including how to hand it your own console
and LED, and the `embedded_on_panic` hook for putting outputs into a safe
state.

A template sets the CPU, the linker script and two features: `BOARD_<name>`
selects the pin map in `src/boards/` and `MCU_<name>` the backend in
`src/backends/`. Every board and backend module is guarded by its feature, so
one manifest target per architecture (`elf-avr`, `elf-riscv32`) serves every
board built on it. Adding an ATmega328P board means a new board file and a
template, nothing else. `manifest.json` also describes each board and MCU in
its `vendor.embedded` block (memory sizes, USB ids, flash tool and settings)
for tools that need that data without parsing C3.

## Examples

```sh
cd examples/blink
c3c build blink-arduino-uno           # release
c3c build blink-esp32c3-debug         # debug template
c3c build flash-arduino-uno --trust=full
```

A project target only needs a type and a template:

```json
"targets": {
  "blink-uno": { "type": "executable", "template": "embedded/arduino_uno" }
}
```

## Flashing

Every example has `flash-arduino-uno` and `flash-esp32c3` targets. They build
the firmware, then run `scripts/flash.c3`, which calls avrdude or esptool with
the settings from the manifest's `vendor.embedded` block and finds the serial
port itself (or takes it from `PORT`). Running a script needs `--trust=full`.
`docs/flashing.md` covers the tools, port selection, dry runs and how to add a
flash target to your own project. `scripts/size.c3` prints flash and RAM use
against the MCU's limits.

## GPIO in short

```c3
import embedded::gpio;
import embedded::board;

// Configure once, get a handle. Handle methods cannot fail and compile to a
// few register accesses.
gpio::Output led = gpio::output(board::Pin.BUILTIN_LED)!;
gpio::Input button = gpio::input(board::Pin.D2, UP)!;
led.write(button.is_low() ? HIGH : LOW);
led.toggle();

// Or by pin number, with a preset or a designated initialiser.
gpio::configure(board::Pin.D3, gpio::CONFIG_INPUT_PULLUP)!;
gpio::configure(board::Pin.D4, { .direction = OUTPUT, .initial_state = HIGH })!;
gpio::write(board::Pin.D4, LOW)!;
```

## Peripherals in short

Each module has its interface in `src/api/<module>.c3i`, which documents the
per-board pins and limits.

```c3
// Serial console (Uno: USB bridge on D0/D1, SuperMini: USB-C port).
uart::Uart console = uart::open(board::CONSOLE)!;
console.write_line("hello");
console.write_uint(time::as_ms(time::since_boot()));

// Analog input, PWM output.
adc::Input pot = adc::open(board::Pin.A0)!;           // GPIO0..4 on the SuperMini
pwm::Channel led = pwm::open(board::Pin.D9, { .frequency_hz = 1000 })!;
led.set_duty(pot.read() * pwm::MAX_DUTY / 1023);      // duty in permille

// Pin interrupt (Uno: D2/D3, SuperMini: any GPIO).
exti::attach(board::Pin.D2, FALLING, &on_button)!;

// Buses on the board's default pins.
i2c::Bus bus = i2c::open({ .frequency_hz = i2c::FAST_HZ })!;
bus.write_read(0x48, { 0x00 }, &buffer)!;
spi::Bus flash = spi::open({ .frequency_hz = 8_000_000, .mode = MODE0 })!;

// Interrupt control.
irq::@critical() { shared_counter = 0; };
time::spin(time::us(10));                             // busy-wait, works with interrupts off
```

The examples cover each module: `uart_echo`, `analog_read`, `pwm_fade`,
`button_irq`, `i2c_scan`, `spi_loopback`. `professional` puts them together
the way production firmware would: a non-blocking main loop of deadline-driven
tasks, faults counted and reported instead of fatal, the watchdog fed once per
pass, and a `panicfn` that reports failed contracts and bounds checks before
the watchdog resets the chip.

## Tests

`test/` holds host-side unit tests for the code that does not touch
hardware: the runtime arithmetic helpers, duration and deadline maths (against
a fake clock), UART number formatting (against a fake port) and the GPIO pin
tables. There is one target per MCU, because each one compiles that MCU's
backend:

```sh
cd test
c3c test atmega328p
c3c test esp32c3
```

CI runs both and, for every example and board, builds the release and the
debug target, runs the flash target as a dry run and reports the sizes. The
nightly release attaches the library archive and a size report of all
examples.

## Startup and memory

The library owns the reset path: it sets up the stack, initialises `.data` and
`.bss`, starts the clock and interrupts, then calls your `start()`. Code that
must run before `start()`, such as board bring-up in a shared package, can
override the weak boot hook:

```c3
fn void board_bring_up() @export("embedded_on_boot") {
    // runs once, after library init, with interrupts on
}
```

The linker scripts reserve a minimum stack (128 bytes on the Uno, 8 KB on the
ESP32-C3) and fail the link if `.data` + `.bss` leave less. Change it per target
with `"link-args": ["--defsym=__stack_size=256"]`. Variables marked
`@section(".noinit")` are neither loaded nor cleared, so they survive a
watchdog reset. `__heap_start`/`__heap_end` mark the free RAM in between.

## Writing a backend

Backends access registers through the macros in `embedded::core`
(`src/core/core.c3`): `@reg_read`, `@reg_write`, `@reg_set_bits`,
`@reg_clear_bits` and `@reg_update`. They take an address and default to the
MCU's register width (8 bits on AVR, 32 on the ESP32-C3); pass a type for
other widths. A file that uses them needs `import embedded::core;`. Register
addresses and fields go in the MCU's `regs.c3`.

## ToDo (central APIs)
- [X] Digital I/O
- [x] Time / monotonic clock (`sleep`, `spin`, `since_boot`)
- [x] Watchdog (enable / feed / disable, reset cause)
- [x] Interrupt control (`irq`: critical sections, vectors / interrupt matrix)
- [x] PWM
- [x] ADC
- [x] UART (+ USB-Serial-JTAG console on the ESP32-C3)
- [x] I2C (master)
- [x] External Interrupts
- [x] SPI (master)
- [ ] Clocks + Timers

Copyright (c) 2026 Johannes (jotrorox) Muller.

Licensed under the MIT License. See LICENSE for details.
