module embedded_test::time;

// src/api/time_common.c3 against the fake clock in support/fake_clock.c3.

import embedded::time;

const ulong MAX = ulong::max;

fn void constructors_scale_to_microseconds() @test {
    assert(time::as_us(time::us(7)) == 7);
    assert(time::as_us(time::ms(7)) == 7_000);
    assert(time::as_us(time::seconds(7)) == 7_000_000);
    assert(time::as_us(time::ms(0)) == 0);
}

fn void constructors_saturate_instead_of_wrapping() @test {
    ulong max_ms = MAX / 1000;
    assert(time::as_us(time::ms(max_ms)) == max_ms * 1000, "largest exact ms value");
    assert(time::as_us(time::ms(max_ms + 1)) == MAX, "one past it saturates");
    assert(time::as_us(time::ms(MAX)) == MAX);

    ulong max_s = MAX / 1_000_000;
    assert(time::as_us(time::seconds(max_s)) == max_s * 1_000_000);
    assert(time::as_us(time::seconds(max_s + 1)) == MAX);
}

fn void as_ms_truncates() @test {
    assert(time::as_ms(time::us(0)) == 0);
    assert(time::as_ms(time::us(999)) == 0);
    assert(time::as_ms(time::us(1000)) == 1);
    assert(time::as_ms(time::us(1999)) == 1);
    assert(time::as_ms(time::us(MAX)) == MAX / 1000);

    // The long division against the host's divider.
    ulong x = 0x9E37_79B9_7F4A_7C15;
    for (int i = 0; i < 100_000; i++) {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        ulong value = x >> (i % 64);
        assert(time::as_ms(time::us(value)) == value / 1000, "as_ms(%d)", value);
    }
}

fn void add_saturates() @test {
    assert(time::as_us(time::duration_add(time::us(2), time::us(3))) == 5);
    assert(time::as_us(time::duration_add(time::us(MAX - 1), time::us(1))) == MAX);
    assert(time::as_us(time::duration_add(time::us(MAX), time::us(1))) == MAX);
    assert(time::as_us(time::duration_add(time::us(MAX), time::us(MAX))) == MAX);
}

fn void sub_saturates_at_zero() @test {
    assert(time::as_us(time::duration_sub_saturating(time::us(5), time::us(3))) == 2);
    assert(time::as_us(time::duration_sub_saturating(time::us(3), time::us(3))) == 0);
    assert(time::as_us(time::duration_sub_saturating(time::us(3), time::us(5))) == 0);
}

fn void is_zero() @test {
    assert(time::duration_is_zero(time::us(0)));
    assert(!time::duration_is_zero(time::us(1)));
}

fn void deadline_expires_after_duration() @test {
    time::fake_set(1_000);
    time::Instant deadline = time::deadline_after(time::us(500));
    assert(!time::has_elapsed(deadline));
    time::fake_advance(499);
    assert(!time::has_elapsed(deadline), "one tick early");
    time::fake_advance(1);
    assert(time::has_elapsed(deadline), "exactly on time");
    time::fake_advance(1_000_000);
    assert(time::has_elapsed(deadline), "long after");
}

fn void zero_deadline_has_elapsed_immediately() @test {
    time::fake_set(42);
    assert(time::has_elapsed(time::deadline_after(time::us(0))));
}

fn void deadline_survives_counter_wrap() @test {
    time::fake_set(MAX - 99);
    time::Instant deadline = time::deadline_after(time::us(200));
    assert(!time::has_elapsed(deadline), "before the wrap");
    time::fake_advance(150); // the counter wraps here
    assert(!time::has_elapsed(deadline), "after the wrap, still early");
    time::fake_advance(50);
    assert(time::has_elapsed(deadline));
}

fn void huge_deadline_is_clamped_into_the_future() @test {
    // Without the clamp, MAX µs ahead is -1 in signed difference: the past.
    time::fake_set(12_345);
    assert(!time::has_elapsed(time::deadline_after(time::us(MAX))));
    assert(!time::has_elapsed(time::deadline_after(time::seconds(MAX))));
    assert(!time::has_elapsed(time::deadline_after(time::us((ulong)1 << 63))));
}

fn void elapsed_between_wraps() @test {
    time::Instant start = { (time::Ticks)(MAX - 9) };
    time::Instant end = { (time::Ticks)20 };
    assert(time::as_us(time::elapsed_between(start, end)) == 30);
}

fn void elapsed_since_and_since_boot_use_now() @test {
    time::fake_set(5_000);
    time::Instant start = time::now();
    time::fake_advance(1_234);
    assert(time::as_us(time::elapsed_since(start)) == 1_234);
    assert(time::as_us(time::since_boot()) == 6_234);
}

fn void sleep_waits_for_the_deadline() @test {
    time::fake_set(100);
    time::sleep(time::ms(3));
    assert(time::as_us(time::since_boot()) == 3_100);

    time::sleep(time::us(0));
    assert(time::as_us(time::since_boot()) == 3_100, "sleep(0) returns at once");
}
