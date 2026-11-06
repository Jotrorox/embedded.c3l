module embedded::board @feat(BOARD_ESP32C3_SUPERMINI);

// A board only works on its MCU. The `embedded/esp32c3_supermini` template sets both
// features; a target that lists its own features must keep them paired.
$assert $feat(MCU_ESP32C3) : "BOARD_ESP32C3_SUPERMINI needs the MCU_ESP32C3 feature (use the embedded/esp32c3_supermini template)";

import embedded::gpio;
import embedded::uart;

constdef Pin : inline gpio::Pin {
    BUILTIN_LED = 8,

    GPIO0  = 0,
    GPIO1  = 1,
    GPIO2  = 2,
    GPIO3  = 3,
    GPIO4  = 4,
    GPIO5  = 5,
    GPIO6  = 6,
    GPIO7  = 7,
    GPIO8  = 8,
    GPIO9  = 9,
    GPIO10 = 10,
    GPIO18 = 18,
    GPIO19 = 19,
    GPIO20 = 20,
    GPIO21 = 21,
}

// The USB-C socket is the chip's USB-Serial-JTAG port.
const uart::Port CONSOLE = uart::Port.USB_SERIAL_JTAG;

// Default bus pins (the common SuperMini pinout). Any GPIO works through the
// GPIO matrix, see `i2c::open_pins()` and `spi::open_pins()`. GPIO8 also
// drives the on-board LED and GPIO9 is the BOOT button; both have pull-ups.
const gpio::Pin I2C_SDA  = Pin.GPIO8;
const gpio::Pin I2C_SCL  = Pin.GPIO9;
const gpio::Pin SPI_SCK  = Pin.GPIO4;
const gpio::Pin SPI_MISO = Pin.GPIO5;
const gpio::Pin SPI_MOSI = Pin.GPIO6;
const gpio::Pin SPI_SS   = Pin.GPIO7;
