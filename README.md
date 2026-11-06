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

- `embedded/arduino_uno`
- `embedded/esp32c3_supermini`

## Examples

```sh
cd examples/blink
c3c build blink-arduino-uno
c3c build blink-esp32c3
```

A project target only needs a type and a template:

```json
"targets": {
  "blink-uno": { "type": "executable", "template": "embedded/arduino_uno" }
}
```

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
`button_irq`, `i2c_scan`, `spi_loopback`.

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
