module embedded::adc;

import embedded::gpio;
import embedded::time;
import embedded::backends::esp32::esp32c3::soc;

// SAR ADC1 through the APB_SARADC "one-time sample" path, following ESP-IDF
// v5.3's adc_oneshot_hal for the ESP32-C3. ADC2 (GPIO5) shares hardware with
// the radio and is not supported.
const uint SARADC_BASE = 0x6004_0000;
const uint SARADC_CTRL           = SARADC_BASE + 0x000;
const uint SARADC_ONETIME_SAMPLE = SARADC_BASE + 0x020;
const uint SARADC_1_DATA_STATUS  = SARADC_BASE + 0x02C;
const uint SARADC_INT_RAW        = SARADC_BASE + 0x044;
const uint SARADC_INT_CLR        = SARADC_BASE + 0x04C;
const uint SARADC_CLKM_CONF      = SARADC_BASE + 0x054;

// CTRL
const uint CTRL_XPD_SAR_FORCE_ON = 3u << 27;
const uint CTRL_XPD_SAR_FORCE_MASK = 3u << 27;
const uint CTRL_SAR_CLK_DIV_MASK = 0xFFu << 7;
const uint CTRL_SAR_CLK_DIV_1 = 1u << 7;
const uint CTRL_SAR_CLK_GATED = 1u << 6;
// ONETIME_SAMPLE
const uint ONETIME_ADC1 = 1u << 31;
const uint ONETIME_START = 1u << 29;
const uint ONETIME_CHANNEL_SHIFT = 25;
const uint ONETIME_ATTEN_SHIFT = 23;
// INT_RAW / INT_CLR
const uint INT_ADC1_ONESHOT_DONE = 1u << 31;
// CLKM_CONF: APB source, enabled, divider 15 + 1 (ESP-IDF defaults).
const uint CLKM_CONF_VALUE = (2u << 21) | (1u << 20) | (1u << 14) | 15;

// RTC_CNTL_SENSOR_CTRL: FORCE_XPD_SAR in bits 31:30 powers the analog part.
const uint RTC_CNTL_SENSOR_CTRL = 0x6000_811C;
const uint FORCE_XPD_SAR_ON = 3u << 30;

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
    soc::enable_peripheral(soc::PERIP_APB_SARADC);
    soc::set_bits(RTC_CNTL_SENSOR_CTRL, FORCE_XPD_SAR_ON);
    soc::write(SARADC_CLKM_CONF, CLKM_CONF_VALUE);
    soc::modify(SARADC_CTRL, CTRL_XPD_SAR_FORCE_MASK | CTRL_SAR_CLK_DIV_MASK | CTRL_SAR_CLK_GATED,
        CTRL_XPD_SAR_FORCE_ON | CTRL_SAR_CLK_DIV_1 | CTRL_SAR_CLK_GATED);
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
    uint sample = ONETIME_ADC1
        | ((uint)self.channel << ONETIME_CHANNEL_SHIFT)
        | ((uint)self.atten << ONETIME_ATTEN_SHIFT);
    soc::write(SARADC_INT_CLR, INT_ADC1_ONESHOT_DONE);
    soc::write(SARADC_ONETIME_SAMPLE, sample);
    // The start edge must last a few ADC controller clocks (APB / 16) to be
    // seen; ESP-IDF waits 3 µs at 80 MHz APB.
    time::spin(time::us(5));
    soc::write(SARADC_ONETIME_SAMPLE, sample | ONETIME_START);
    while ((soc::read(SARADC_INT_RAW) & INT_ADC1_ONESHOT_DONE) == 0) {}
    ushort raw = (ushort)(soc::read(SARADC_1_DATA_STATUS) & 0xFFF);
    soc::write(SARADC_ONETIME_SAMPLE, 0);
    return raw;
}

fn uint Input.read_millivolts(self) {
    uint full_scale = self.atten == ATTEN_11DB ? 2500 : 750;
    return (uint)self.read() * full_scale / 4095;
}
