module embedded::rt @feat(!BACKEND_AVR);

// 64-bit shifts, built everywhere but AVR (where C `int` is 16 bits and LLVM
// does not call these).

fn void shifts_match_native_for_every_amount() @test {
    ulong[*] values = { 0, 1, 0x8000_0000_0000_0000, ulong::max, 0x0123_4567_89AB_CDEF, 0xFEDC_BA98_7654_3210 };
    foreach (v : values) {
        for (int b = 0; b < 64; b++) {
            assert(__lshrdi3(v, b) == v >> b, "%x >> %d", v, b);
            assert(__ashldi3(v, b) == v << b, "%x << %d", v, b);
            assert(__ashrdi3((long)v, b) == (long)v >> b, "%x >>> %d", v, b);
        }
    }
}
