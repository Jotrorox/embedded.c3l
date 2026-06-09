# embedded.c3l

`embedded.c3l` is a source-selected embedded HAL for C3.

Board presets select the active board and MCU backend. Application code should
not import AVR, ESP32-C3, or other backend-specific modules directly.

## Supported Presets

- `embedded:arduino_uno`
- `embedded:esp32c3_supermini`

## Examples

```sh
cd examples/blink
c3c build blink-arduino-uno
c3c build blink-esp32c3
```

## ToDo (central APIs)
- [X] Digital I/O
- [x] Time / monotonic clock
- [ ] PWM
- [ ] ADC
- [ ] UART
- [ ] I2C
- [ ] External Interrupts
- [ ] SPI
- [ ] Clocks + Timers

Copyright (c) 2026 Johannes (jotrorox) Muller.

Licensed under the MIT License. See LICENSE for details.
