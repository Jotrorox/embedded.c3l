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

## ToDo (central APIs)
- [X] Digital I/O
- [x] Time / monotonic clock
- [x] Watchdog (enable / feed / disable, reset cause)
- [ ] PWM
- [ ] ADC
- [ ] UART
- [ ] I2C
- [ ] External Interrupts
- [ ] SPI
- [ ] Clocks + Timers

Copyright (c) 2026 Johannes (jotrorox) Muller.

Licensed under the MIT License. See LICENSE for details.
