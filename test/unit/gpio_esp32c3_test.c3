module embedded::gpio @feat(MCU_ESP32C3);

// ESP32-C3 GPIO numbers and register addresses (TRM chapter 5; ESP-IDF
// soc/esp32c3/include/soc/io_mux_reg.h and gpio_reg.h). GPIO11-17 are the
// SPI flash pins and are not offered.

fn void valid_pins() @test {
    for (int p = 0; p <= 21; p++) {
        bool want = p <= 10 || p >= 18;
        assert(is_valid((Pin)p) == want, "pin %d", p);
    }
    assert(!is_valid((Pin)22));
}

fn void register_addresses() @test {
    assert(pin_io_mux_reg((Pin)0) == 0x6000_9004);
    assert(pin_io_mux_reg((Pin)21) == 0x6000_9058);
    assert(pin_out_sel_reg((Pin)0) == 0x6000_4554);
    assert(pin_out_sel_reg((Pin)21) == 0x6000_45A8);
    for (int p = 0; p <= 21; p++) assert(pin_mask((Pin)p) == 1u << p);
}

fn void capabilities() @test {
    assert(supports((Pin)9, Capability.PULL_UP));
    assert(supports((Pin)9, Capability.PULL_DOWN));
    assert(!supports((Pin)9, Capability.OPEN_DRAIN));
    assert(!supports((Pin)12, Capability.INPUT), "flash pin");
}
