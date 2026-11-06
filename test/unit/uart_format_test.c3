module embedded_test::uart_format;

// src/api/uart_format.c3 against the fake port in support/fake_uart.c3.

import embedded::uart;
import embedded::time;

macro void expect_output(String expected) {
    String got = (String)uart::fake_output();
    assert(got == expected, "wrote \"%s\", expected \"%s\"", got, expected);
    uart::fake_reset();
}

fn uart::Uart port() {
    uart::fake_reset();
    return { (uart::Port)0 };
}

fn void write_uint_small_values() @test {
    uart::Uart u = port();
    u.write_uint(0);
    expect_output("0");
    u.write_uint(7);
    expect_output("7");
    u.write_uint(10);
    expect_output("10");
    u.write_uint(65_535);
    expect_output("65535");
}

fn void write_uint_at_the_32_bit_boundary() @test {
    // Values up to 2^32 - 1 take the 32-bit path, larger ones the long division.
    uart::Uart u = port();
    u.write_uint(4_294_967_295);
    expect_output("4294967295");
    u.write_uint(4_294_967_296);
    expect_output("4294967296");
    u.write_uint(ulong::max);
    expect_output("18446744073709551615");
}

fn void write_uint_matches_a_reference() @test {
    uart::Uart u = port();
    ulong x = 0x2545_F491_4F6C_DD1D;
    char[20] expected;
    for (int i = 0; i < 20_000; i++) {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        ulong value = x >> (i % 64);

        usz len = 0;
        ulong rest = value;
        do {
            expected[19 - len++] = (char)('0' + rest % 10);
            rest /= 10;
        } while (rest != 0);

        u.write_uint(value);
        expect_output((String)expected[20 - len..]);
    }
}

fn void write_int_signs() @test {
    uart::Uart u = port();
    u.write_int(0);
    expect_output("0");
    u.write_int(-1);
    expect_output("-1");
    u.write_int(long::max);
    expect_output("9223372036854775807");
    u.write_int(long::min);
    expect_output("-9223372036854775808");
}

fn void write_hex_digits_and_padding() @test {
    uart::Uart u = port();
    u.write_hex(0);
    expect_output("0");
    u.write_hex(0xF);
    expect_output("F");
    u.write_hex(0xDEAD_BEEF);
    expect_output("DEADBEEF");
    u.write_hex(0xFF, 4);
    expect_output("00FF");
    u.write_hex(0x1234, 2);
    expect_output("1234");
    u.write_hex(0, 0);
    expect_output("0");
    u.write_hex(ulong::max);
    expect_output("FFFFFFFFFFFFFFFF");
    u.write_hex(1, 20);
    expect_output("0000000000000001");
}

fn void write_line_appends_crlf() @test {
    uart::Uart u = port();
    u.write_line("ok");
    expect_output("ok\r\n");
}

fn void read_byte_returns_queued_data() @test {
    uart::Uart u = port();
    uart::fake_rx = "ab";
    time::fake_set(0);
    char a = u.read_byte(time::ms(1))!!;
    char b = u.read_byte(time::ms(1))!!;
    assert(a == 'a' && b == 'b');
}

fn void read_byte_times_out() @test {
    uart::Uart u = port();
    time::fake_set(1_000);
    char? byte = u.read_byte(time::ms(5));
    assert(@catch(byte) == uart::TIMEOUT);
    // It polled until the deadline and no further than one extra poll.
    ulong waited = time::as_us(time::since_boot()) - 1_000;
    assert(waited >= 5_000 && waited <= 5_000 + uart::fake_read_cost_us, "waited %d us", waited);
}
