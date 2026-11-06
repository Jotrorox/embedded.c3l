module embedded::board @feat(BOARD_ARDUINO_UNO);

// A board only works on its MCU. The `embedded/arduino_uno` template sets both
// features; a target that lists its own features must keep them paired.
$assert $feat(MCU_ATMEGA328P) : "BOARD_ARDUINO_UNO needs the MCU_ATMEGA328P feature (use the embedded/arduino_uno template)";

import embedded::gpio;
import embedded::uart;

constdef Pin : inline gpio::Pin {
    BUILTIN_LED = 13,

    D0  = 0,
    D1  = 1,
    D2  = 2,
    D3  = 3,
    D4  = 4,
    D5  = 5,
    D6  = 6,
    D7  = 7,
    D8  = 8,
    D9  = 9,
    D10 = 10,
    D11 = 11,
    D12 = 12,
    D13 = 13,

    A0 = 14,
    A1 = 15,
    A2 = 16,
    A3 = 17,
    A4 = 18,
    A5 = 19,
}

// The serial port wired to the Uno's USB bridge (D0/D1).
const uart::Port CONSOLE = uart::Port.UART0;

// Pins of the ATmega328P's fixed bus peripherals. The backends use these
// pins whatever is passed here; they are listed so code can refer to them.
const gpio::Pin I2C_SDA  = Pin.A4;
const gpio::Pin I2C_SCL  = Pin.A5;
const gpio::Pin SPI_SCK  = Pin.D13;
const gpio::Pin SPI_MISO = Pin.D12;
const gpio::Pin SPI_MOSI = Pin.D11;
const gpio::Pin SPI_SS   = Pin.D10;
