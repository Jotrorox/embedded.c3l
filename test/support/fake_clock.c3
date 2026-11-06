module embedded::time;

// Host stand-in for a backend clock: `now()` returns a tick count the test
// sets. Ticks are microseconds, as on both real backends.

Ticks fake_ticks;

fn void fake_set(ulong micros) => fake_ticks = (Ticks)micros;
fn void fake_advance(ulong micros) => fake_ticks = (Ticks)(fake_ticks + micros);

fn ClockInfo clock_info() => { 1_000_000, 1, true, true };
fn Instant now() => { fake_ticks };

fn void sleep_until(Instant deadline) {
    if (!has_elapsed(deadline)) fake_ticks = deadline.ticks;
}

fn void spin(Duration duration) => fake_advance(duration.micros);
