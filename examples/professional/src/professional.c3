module professional;

import embedded::board;
import embedded::gpio;
import embedded::panic;
import embedded::time;
import embedded::uart;
import embedded::wdt;

// A main loop for firmware that has to keep running unattended.
//
// - Nothing blocks. Each task checks its own deadline and returns at once when
//   there is nothing to do, so one task cannot starve the others.
// - The watchdog is fed once per pass of the loop. If anything hangs, feeding
//   stops and the chip resets; the next boot reports it.
// - Recoverable faults (a missing console or button, UART line errors) are
//   counted and reported, never fatal.
// - Bugs are not recoverable. This target builds with `safe` on, so a failed
//   contract, assert or bounds check calls the library's panic handler
//   (`embedded::panic::handler`, named by `panicfn` in project.json). It
//   switches the LED off through the `embedded_on_panic` hook, reports where
//   the panic happened on the console, then lets the watchdog reset the chip.
//
// Keeping the checks in costs space: on the Uno about 2.4 KB of flash and 0.8 KB
// of SRAM (AVR keeps the panic texts in RAM). Without `safe`, checks compile
// to nothing and the handler is never called. The `<board>_debug` templates
// turn the same checks on for any project.
//
// Console (115200 baud on the Uno, any baud on the SuperMini's USB port):
//   s  print the status report now
//   p  break a contract, to see the panic path
//   h  hang the main loop, to see the watchdog reset
//
// Button: between D2 and GND on the Uno, the BOOT button (GPIO9) on the
// SuperMini.

const gpio::Pin BUTTON_PIN @feat(BOARD_ARDUINO_UNO) = board::Pin.D2;
const gpio::Pin BUTTON_PIN @feat(BOARD_ESP32C3_SUPERMINI) = board::Pin.GPIO9;

const ulong WATCHDOG_MS = 500;
const ulong HEARTBEAT_MS = 500;
const ulong BUTTON_POLL_MS = 5;
const char DEBOUNCE_SAMPLES = 4; // 4 x 5 ms of a steady level
const ulong REPORT_MS = 10_000;

// ---------------------------------------------------------------------------
// Peripherals. Globals, because the panic handler needs them too. Each has a
// flag: the firmware keeps running when one fails to open.

uart::Uart console;
bool console_ok;
gpio::Output led;
bool led_ok;

fn void say(String text) {
    if (console_ok) console.write_line(text);
}

// ---------------------------------------------------------------------------
// Periodic tasks.

struct Task {
    time::Duration period;
    time::Instant next;
}

// The period is converted once here, not on every check: `time::ms()` is a
// 64-bit multiply, which is slow on the ATmega328P.
fn Task every_ms(ulong period_ms) {
    time::Duration period = time::ms(period_ms);
    return { period, time::deadline_after(period) };
}

// True at most once per period. The next deadline counts from now, so a late
// pass pushes the schedule back rather than causing a burst of catch-up runs.
fn bool Task.due(&self) {
    if (!time::has_elapsed(self.next)) return false;
    self.next = time::deadline_after(self.period);
    return true;
}

<*
 @require period_ms > 0 : "a zero period would run the task on every pass"
*>
fn void Task.set_period_ms(&self, ulong period_ms) {
    self.period = time::ms(period_ms);
}

// ---------------------------------------------------------------------------
// Button: polled and debounced, so it needs no interrupt and no delay.

struct Debouncer {
    gpio::Input input;
    bool pressed;
    char streak;
}

// Returns true once per press, after the level has been steady for
// DEBOUNCE_SAMPLES polls.
fn bool Debouncer.poll(&self) {
    bool low = self.input.is_low(); // active low, pulled up
    if (low == self.pressed) {
        self.streak = 0;
        return false;
    }
    if (++self.streak < DEBOUNCE_SAMPLES) return false;
    self.streak = 0;
    self.pressed = low;
    return low;
}

// ---------------------------------------------------------------------------
// Status.

struct Stats {
    uint button_presses;
    uint uart_errors;
    ulong worst_pass_us; // longest loop pass since the last report
}

fn void report(Stats* stats, bool watchdog_on) {
    if (!console_ok) return;
    console.write("uptime_ms=");
    console.write_uint(time::as_ms(time::since_boot()));
    console.write(" presses=");
    console.write_uint(stats.button_presses);
    console.write(" uart_errors=");
    console.write_uint(stats.uart_errors);
    console.write(" worst_pass_us=");
    console.write_uint(stats.worst_pass_us);
    console.write_line(watchdog_on ? " watchdog=on" : " watchdog=off");
    stats.worst_pass_us = 0;
}

// Handles at most one byte per pass, so a flood of input cannot stall the
// other tasks.
fn void poll_console(Stats* stats, Task* heartbeat, bool watchdog_on) {
    if (!console_ok) return;
    char? byte = console.try_read();
    if (catch err = byte) {
        if (err != uart::NO_DATA) stats.uart_errors++; // framing, parity, overrun
        return;
    }
    switch (byte) {
        case 's':
            report(stats, watchdog_on);
        case 'p':
            say("breaking a contract...");
            // A runtime zero: with a literal 0 the compiler would reject the
            // call at compile time instead.
            heartbeat.set_period_ms((ulong)(byte - 'p'));
        case 'h':
            say("hanging; the watchdog should reset the chip");
            // A loop with a body: c3c turns an empty `while (true) {}` into a
            // trap, which on AVR is no instruction at all.
            while (true) time::spin(time::ms(1));
        default:
    }
}

// ---------------------------------------------------------------------------
// Called once by the library's panic handler, before it reports and resets,
// with interrupts off. This is the place to put outputs into a safe state; here
// the LED goes dark so the panic blink that follows is easy to tell apart from
// the heartbeat.

fn void safe_state() @export("embedded_on_panic") {
    if (led_ok) led.clear();
}

// ---------------------------------------------------------------------------

fn void firmware_start() @export("start") {
    bool watchdog_reset = wdt::caused_reset();

    if (try c = uart::open(board::CONSOLE)) {
        console = c;
        console_ok = true;
        panic::report_to(console);
    }
    if (try l = gpio::output(board::Pin.BUILTIN_LED)) {
        led = l;
        led_ok = true;
        panic::signal_with(led);
    }
    Debouncer button;
    bool button_ok;
    if (try b = gpio::input(BUTTON_PIN, UP)) {
        button = { .input = b };
        button_ok = true;
    }

    say("professional: booted (s = status, p = panic, h = hang)");
    if (watchdog_reset) say("last reset: watchdog");
    if (!led_ok) say("fault: LED unavailable");
    if (!button_ok) say("fault: button unavailable");

    bool watchdog_on = true;
    if (catch wdt::enable(time::ms(WATCHDOG_MS))) {
        watchdog_on = false;
        say("fault: watchdog unavailable, running without it");
    }

    Stats stats;
    Task heartbeat = every_ms(HEARTBEAT_MS);
    Task button_poll = every_ms(BUTTON_POLL_MS);
    Task status = every_ms(REPORT_MS);

    while (true) {
        time::Instant pass_start = time::now();

        if (led_ok && heartbeat.due()) led.toggle();

        if (button_ok && button_poll.due() && button.poll()) {
            stats.button_presses++;
            say("button pressed");
        }

        poll_console(&stats, &heartbeat, watchdog_on);

        if (status.due()) report(&stats, watchdog_on);

        ulong pass_us = time::as_us(time::elapsed_since(pass_start));
        if (pass_us > stats.worst_pass_us) stats.worst_pass_us = pass_us;

        wdt::feed();
    }
}
