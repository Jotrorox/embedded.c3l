module embedded::rt;

// The compiler-rt replacements in src/rt/ against the host's own arithmetic.
// These tests sit in the runtime's module because it is @private.

struct Rng {
    ulong state;
}

fn ulong Rng.next(&self) {
    self.state ^= self.state << 13;
    self.state ^= self.state >> 7;
    self.state ^= self.state << 17;
    return self.state;
}

// Random values with a random bit width, so small and large operands both
// show up, plus the edge cases that broke real implementations.
fn ulong Rng.operand(&self) {
    ulong v = self.next();
    switch (v & 7) {
        case 0: return 0;
        case 1: return 1;
        case 2: return ulong::max;
        case 3: return (ulong)1 << (v >> 58);
        default: return self.next() >> (v >> 58);
    }
}

const int ROUNDS = 200_000;

fn void mulsi3_matches_native() @test {
    Rng rng = { 0x1234_5678_9ABC_DEF1 };
    for (int i = 0; i < ROUNDS; i++) {
        int a = (int)rng.operand();
        int b = (int)rng.operand();
        assert(__mulsi3(a, b) == (int)((uint)a * (uint)b), "%d * %d", a, b);
    }
}

fn void udivmodsi_matches_native() @test {
    Rng rng = { 0xCAFE_F00D_DEAD_BEEF };
    for (int i = 0; i < ROUNDS; i++) {
        uint a = (uint)rng.operand();
        uint b = (uint)rng.operand();
        if (b == 0) continue;
        assert(__udivsi3(a, b) == a / b, "%d / %d", a, b);
        assert(__umodsi3(a, b) == a % b, "%d %% %d", a, b);
    }
    // The case that once returned 0: dividend with the top bit set.
    assert(__udivsi3(0x8000_0000, 3) == 0x8000_0000u / 3);
    assert(__udivsi3(uint::max, 1) == uint::max);
}

fn void divmodsi_matches_native() @test {
    Rng rng = { 0x0F0F_0F0F_1234_4321 };
    for (int i = 0; i < ROUNDS; i++) {
        int a = (int)rng.operand();
        int b = (int)rng.operand();
        if (b == 0 || (a == int::min && b == -1)) continue;
        assert(__divsi3(a, b) == a / b, "%d / %d", a, b);
        assert(__modsi3(a, b) == a % b, "%d %% %d", a, b);
    }
}

fn void muldi3_matches_native() @test {
    Rng rng = { 0x5555_AAAA_3333_CCCC };
    for (int i = 0; i < ROUNDS; i++) {
        long a = (long)rng.operand();
        long b = (long)rng.operand();
        assert(__muldi3(a, b) == (long)((ulong)a * (ulong)b), "%d * %d", a, b);
    }
}

fn void udivmoddi_matches_native() @test {
    Rng rng = { 0x9E37_79B9_7F4A_7C15 };
    for (int i = 0; i < ROUNDS; i++) {
        ulong a = rng.operand();
        ulong b = rng.operand();
        if (b == 0) continue;
        assert(__udivdi3(a, b) == a / b, "%d / %d", a, b);
        assert(__umoddi3(a, b) == a % b, "%d %% %d", a, b);
    }
    assert(__udivdi3(ulong::max, 1) == ulong::max);
    assert(__udivdi3((ulong)1 << 63, 3) == ((ulong)1 << 63) / 3);
}

fn void divmoddi_matches_native() @test {
    Rng rng = { 0x7777_1111_EEEE_2222 };
    for (int i = 0; i < ROUNDS; i++) {
        long a = (long)rng.operand();
        long b = (long)rng.operand();
        if (b == 0 || (a == long::min && b == -1)) continue;
        assert(__divdi3(a, b) == a / b, "%d / %d", a, b);
        assert(__moddi3(a, b) == a % b, "%d %% %d", a, b);
    }
}

fn void memset_fills_exactly_the_range() @test {
    char[16] buf;
    for (usz i = 0; i < buf.len; i++) buf[i] = 0xAA;
    memset(&buf[3], 0x1234, 5); // only the low byte counts
    for (usz i = 0; i < buf.len; i++) {
        char want = i >= 3 && i < 8 ? 0x34 : 0xAA;
        assert(buf[i] == want, "byte %d is %d", i, buf[i]);
    }
    assert(memset(&buf, 0, 0) == &buf);
}

fn void memcpy_copies_exactly_the_range() @test {
    char[8] src = { 1, 2, 3, 4, 5, 6, 7, 8 };
    char[8] dst;
    assert(memcpy(&dst[1], &src[2], 4) == &dst[1]);
    char[8] want = { 0, 3, 4, 5, 6, 0, 0, 0 };
    for (usz i = 0; i < dst.len; i++) assert(dst[i] == want[i], "byte %d", i);
}

fn void memmove_handles_both_overlaps() @test {
    char[8] fwd = { 1, 2, 3, 4, 5, 6, 7, 8 };
    memmove(&fwd[0], &fwd[2], 5); // destination before source
    char[8] want_fwd = { 3, 4, 5, 6, 7, 6, 7, 8 };
    for (usz i = 0; i < 8; i++) assert(fwd[i] == want_fwd[i], "forward byte %d", i);

    char[8] back = { 1, 2, 3, 4, 5, 6, 7, 8 };
    memmove(&back[2], &back[0], 5); // destination after source
    char[8] want_back = { 1, 2, 1, 2, 3, 4, 5, 8 };
    for (usz i = 0; i < 8; i++) assert(back[i] == want_back[i], "backward byte %d", i);
}
