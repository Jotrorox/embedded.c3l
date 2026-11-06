module pwm_fade;

import embedded::pwm;
import embedded::gpio;
import embedded::time;
import embedded::board;

// Fades an LED up and down. On the Uno connect an LED (with a resistor) to D9;
// on the SuperMini the on-board LED on GPIO8 is used, which is active low, so
// it is brightest at duty 0.
const gpio::Pin LED_PIN @feat(BOARD_ARDUINO_UNO) = board::Pin.D9;
const gpio::Pin LED_PIN @feat(BOARD_ESP32C3_SUPERMINI) = board::Pin.BUILTIN_LED;

fn void firmware_start() @export("start") {
    pwm::Channel led = pwm::open(LED_PIN, { .frequency_hz = 1000 })!!;

    uint duty = 0;
    int step = 10;
    while (true) {
        led.set_duty(duty);
        time::sleep(time::ms(10));
        if (duty == 0 && step < 0 || duty == pwm::MAX_DUTY && step > 0) step = -step;
        duty = (uint)((int)duty + step);
    }
}
