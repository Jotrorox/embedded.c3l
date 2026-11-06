module embedded::adc;

import embedded::gpio;
import embedded::time;
import embedded::backends::esp32::esp32c3::soc;
import embedded::backends::esp32::esp32c3::regs;

// SAR ADC1 through the APB_SARADC "one-time sample" path, following ESP-IDF
// v5.3's adc_oneshot_hal for the ESP32-C3. ADC2 (GPIO5) shares hardware with
// the radio and is not supported.
// CLKM_CONF: APB source, enabled, divider 15 + 1 (ESP-IDF defaults).
const uint CLKM_CONF_VALUE = (regs::SARADC_CLKM_CLK_SEL_APB << regs::SARADC_CLKM_CLK_SEL_SHIFT)
    | regs::SARADC_CLKM_CLK_EN | (1u << regs::SARADC_CLKM_DIV_A_SHIFT) | (15u << regs::SARADC_CLKM_DIV_NUM_SHIFT);

const uint ATTEN_0DB = 0;
const uint ATTEN_11DB = 3;
const uint CHANNEL_COUNT = 5;

struct Input {
    char channel;
    char atten;
}

bool adc_ready @local = false;

fn bool supports(gpio::Pin pin) => (uint)pin < CHANNEL_COUNT;
fn bool supports_reference(Reference reference) => reference == Reference.DEFAULT || reference == Reference.INTERNAL;
fn char resolution_bits() => 12;

fn uint full_scale_millivolts(Reference reference) {
    switch (reference) {
        case Reference.DEFAULT:  return 2500;
        case Reference.INTERNAL: return 750;
        default: return 0;
    }
}

fn void init() @local {
    soc::enable_peripheral(regs::PERIP_APB_SARADC);
    soc::set_bits(regs::RTC_CNTL_SENSOR_CTRL, regs::RTC_CNTL_FORCE_XPD_SAR_ON);
    soc::write(regs::SARADC_CLKM_CONF, CLKM_CONF_VALUE);
    soc::modify(regs::SARADC_CTRL, regs::SARADC_CTRL_XPD_SAR_FORCE_MASK | regs::SARADC_CTRL_SAR_CLK_DIV_MASK | regs::SARADC_CTRL_SAR_CLK_GATED,
        regs::SARADC_CTRL_XPD_SAR_FORCE_ON | (1u << regs::SARADC_CTRL_SAR_CLK_DIV_SHIFT) | regs::SARADC_CTRL_SAR_CLK_GATED);
    adc_ready = true;
}

fn Input? open(gpio::Pin pin, Config config = {}) {
    if (!supports(pin)) return PIN_NOT_ANALOG_CAPABLE~;
    uint atten;
    switch (config.reference) {
        case Reference.DEFAULT:  atten = ATTEN_11DB;
        case Reference.INTERNAL: atten = ATTEN_0DB;
        default: return UNSUPPORTED_REFERENCE~;
    }
    if (!adc_ready) init();
    soc::make_analog(pin);
    return { (char)pin, (char)atten };
}

fn ushort? read(gpio::Pin pin) {
    Input input = open(pin)!;
    return input.read();
}

fn ushort Input.read(self) {
    uint sample = regs::SARADC_ONETIME_ADC1
        | ((uint)self.channel << regs::SARADC_ONETIME_CHANNEL_SHIFT)
        | ((uint)self.atten << regs::SARADC_ONETIME_ATTEN_SHIFT);
    soc::write(regs::SARADC_INT_CLR, regs::SARADC_INT_ADC1_DONE);
    soc::write(regs::SARADC_ONETIME_SAMPLE, sample);
    // The start edge must last a few ADC controller clocks (APB / 16) to be
    // seen; ESP-IDF waits 3 µs at 80 MHz APB.
    time::spin(time::us(5));
    soc::write(regs::SARADC_ONETIME_SAMPLE, sample | regs::SARADC_ONETIME_START);
    while ((soc::read(regs::SARADC_INT_RAW) & regs::SARADC_INT_ADC1_DONE) == 0) {}
    ushort raw = (ushort)(soc::read(regs::SARADC_1_DATA_STATUS) & regs::SARADC_1_DATA_MASK);
    soc::write(regs::SARADC_ONETIME_SAMPLE, 0);
    return raw;
}

fn uint Input.read_millivolts(self) {
    uint full_scale = self.atten == ATTEN_11DB ? 2500 : 750;
    return (uint)self.read() * full_scale / 4095;
}
