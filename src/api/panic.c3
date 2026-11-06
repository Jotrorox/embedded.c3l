module embedded::panic;

import embedded::board;
import embedded::gpio;
import embedded::irq;
import embedded::time;
import embedded::uart;
import embedded::wdt;

// A panic handler for firmware built with safety checks on.
//
// With `safe` on, every failed contract, assert, bounds or null check calls
// the function named by `panicfn`. The `<board>_debug` templates name
// `embedded::panic::handler`; a target on a release template can opt in with
//
//     "safe": true, "panic-msg": true, "panicfn": "embedded::panic::handler"
//
// The handler disables interrupts, calls the `embedded_on_panic` hook once,
// writes the message and location to the console, then arms the watchdog and
// flashes the built-in LED until the chip resets. It never returns.
//
// By default it opens `board::CONSOLE` at `uart::DEFAULT_BAUD` and drives
// `board::Pin.BUILTIN_LED` itself. Firmware that already owns them, or uses a
// different baud rate or pins, hands them over once at start-up:
//
//     panic::report_to(console);
//     panic::signal_with(status_led);
//
// To put outputs into a safe state before the report (motors off, heater off),
// override the hook. It runs with interrupts off and must not rely on them:
//
//     fn void safe_state() @export("embedded_on_panic") { ... }
//
// Without the standard library there is no formatter, so `fmt` and `args`
// are not expanded. On AVR the panic texts live in SRAM (about 0.8 KB in the
// `professional` example), see the README.

// How long the watchdog waits before resetting the chip after a panic.
const ulong RESET_AFTER_MS = 500;

uart::Uart console @local;
bool has_console @local;
gpio::Output led @local;
bool has_led @local;
bool in_panic @local;

// Sends panic reports to `port` instead of the default console.
fn void report_to(uart::Uart port) {
    console = port;
    has_console = true;
}

// Flashes `output` after a panic instead of the built-in LED.
fn void signal_with(gpio::Output output) {
    led = output;
    has_led = true;
}

fn void on_panic() @weak @export("embedded_on_panic") {
}

fn void handler(String summary, String file, String function, int line, String fmt, any[] args) {
    irq::disable();
    // Everything up to the reset runs once. A panic inside the hook or the
    // report goes straight to the reset.
    if (!in_panic) {
        in_panic = true;
        on_panic();
        report(summary.len ? summary : fmt, file, function, line);
    }
    if (catch wdt::enable(time::ms(RESET_AFTER_MS))) {}
    if (!has_led) {
        if (try l = gpio::output(board::Pin.BUILTIN_LED)) {
            led = l;
            has_led = true;
        }
    }
    while (true) {
        if (has_led) led.toggle();
        time::spin(time::ms(50));
    }
}

fn void report(String message, String file, String function, int line) @local {
    if (!has_console) {
        if (try c = uart::open(board::CONSOLE)) {
            console = c;
            has_console = true;
        }
    }
    if (!has_console) return;
    console.write("\r\nPANIC: ");
    console.write_line(message);
    if (file.len) {
        console.write("  at ");
        console.write(file);
        console.write(":");
        console.write_int(line);
        if (function.len) {
            console.write(" in ");
            console.write(function);
        }
        console.write_line("");
    }
    console.flush();
}
