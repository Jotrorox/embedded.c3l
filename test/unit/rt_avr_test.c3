module embedded::rt::avr @feat(BACKEND_AVR);

// The avr-gcc libgcc ABI helpers. They return the quotient in the low half
// and the remainder in the high half; a swap of the two once made every
// 16- and 32-bit `/` and `%` on AVR wrong.

fn void mulqi3_exhaustive() @test {
    for (int a = -128; a < 128; a++) {
        for (int b = -128; b < 128; b++) {
            assert(__mulqi3((ichar)a, (ichar)b) == (ichar)(a * b), "%d * %d", a, b);
        }
    }
}

fn void udivmodqi4_exhaustive() @test {
    for (int a = 0; a < 256; a++) {
        for (int b = 1; b < 256; b++) {
            ushort r = __udivmodqi4((char)a, (char)b);
            assert((char)r == a / b, "%d / %d", a, b);
            assert((char)(r >> 8) == a % b, "%d %% %d", a, b);
        }
    }
}

fn void divmodqi4_exhaustive() @test {
    for (int a = -128; a < 128; a++) {
        for (int b = -128; b < 128; b++) {
            if (b == 0) continue;
            ushort r = __divmodqi4((ichar)a, (ichar)b);
            assert((ichar)r == (ichar)(a / b), "%d / %d", a, b);
            assert((ichar)(r >> 8) == (ichar)(a % b), "%d %% %d", a, b);
        }
    }
}

fn void mulhi3_and_divmodhi4_sampled() @test {
    // Every dividend against a spread of divisors, both signs.
    for (int a = -32768; a < 32768; a += 7) {
        for (int b = -32768; b < 32768; b += 251) {
            assert(__mulhi3((short)a, (short)b) == (short)(a * b), "%d * %d", a, b);
            if (b == 0) continue;
            uint s = __divmodhi4((short)a, (short)b);
            assert((short)s == (short)(a / b), "%d / %d", a, b);
            assert((short)(s >> 16) == (short)(a % b), "%d %% %d", a, b);
            uint ua = (uint)(ushort)a;
            uint ub = (uint)(ushort)b;
            uint u = __udivmodhi4((ushort)ua, (ushort)ub);
            assert((ushort)u == ua / ub, "%d / %d", ua, ub);
            assert((ushort)(u >> 16) == ua % ub, "%d %% %d", ua, ub);
        }
    }
}

fn void divmodsi4_sampled() @test {
    ulong x = 0xD1B5_4A32_D192_ED03;
    for (int i = 0; i < 200_000; i++) {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        uint ua = (uint)(x >> (x & 31));
        uint ub = (uint)((x >> 32) >> ((x >> 5) & 31));
        if (ub == 0) continue;
        ulong u = __udivmodsi4(ua, ub);
        assert((uint)u == ua / ub, "%d / %d", ua, ub);
        assert((uint)(u >> 32) == ua % ub, "%d %% %d", ua, ub);

        long a = (long)(int)ua;
        long b = (long)(int)ub;
        ulong s = __divmodsi4((int)a, (int)b);
        assert((int)(uint)s == (int)(a / b), "%d / %d", a, b);
        assert((int)(uint)(s >> 32) == (int)(a % b), "%d %% %d", a, b);
    }
}

fn void divide_by_zero_follows_libgcc() @test {
    // All-ones quotient, dividend as remainder.
    assert(__udivmodqi4(123, 0) == (ushort)123 << 8 | 0xFF);
    assert(__udivmodhi4(12345, 0) == (uint)12345 << 16 | 0xFFFF);
    assert(__udivmodsi4(123456789, 0) == (ulong)123456789 << 32 | 0xFFFF_FFFF);
}
