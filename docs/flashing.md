# Flashing

`scripts/flash.c3` flashes a firmware ELF onto a board. It reads the flash
settings (tool, chip, programmer, baud, offset, port pattern) from the board's
entry in `manifest.json` (`vendor.embedded.boards.<board>.flash`), so there is
one source of truth for them.

## Tools

| Board | Tool | Notes |
|---|---|---|
| Arduino Uno | `avrdude` 7.0 or newer | Reads the ELF directly, no HEX conversion. |
| ESP32-C3 SuperMini | `esptool` (v5) or `esptool.py` (v4) | Converts the ELF with `elf2image`, then writes it at 0x0. The `.bin` lands next to the ELF. |

Both must be on `PATH`. On macOS: `brew install avrdude esptool`. On Linux use
the distribution's `avrdude` and `pipx install esptool`.

## From the examples

Every example has a `flash-<board>` target. It builds the firmware first and
then runs the script:

```sh
cd examples/blink
c3c build flash-arduino-uno --trust=full
c3c build flash-esp32c3 --trust=full
```

`--trust=full` is required because the target runs a script. c3c never runs
`exec` steps without it.

## Choosing the port

The script uses, in order:

1. `--port <port>` in the target's `exec` line,
2. the `PORT` environment variable: `PORT=/dev/cu.usbmodem1101 c3c build flash-arduino-uno --trust=full`,
3. the only serial port matching the board's pattern for the OS
   (`/dev/cu.usbmodem*` on macOS, `/dev/ttyACM*` on Linux).

When several ports match (for example both boards plugged in on macOS, where
both show up as `cu.usbmodem*`), the script lists them and stops. Set `PORT`.
On Windows ports cannot be listed this way, so set `PORT=COM3` and so on. For
the ESP32-C3, esptool finds the port itself when none is found.

## Checking without a board

`FLASH_DRY_RUN=1` (or `--dry-run`) prints the commands instead of running them.
CI uses it to exercise every flash target:

```sh
FLASH_DRY_RUN=1 c3c build flash-esp32c3 --trust=full
```

## In your own project

Add a `prepare` target that depends on the firmware target. `script-dir` points
at the library's `scripts/` directory and `exec-dir` keeps the working
directory at the project, so the ELF path stays relative to it:

```json
"targets": {
  "firmware-uno": { "type": "executable", "template": "embedded/arduino_uno" },
  "flash-uno": {
    "type": "prepare",
    "depends-on": [ "firmware-uno" ],
    "script-dir": "lib/embedded.c3l/scripts",
    "exec-dir": ".",
    "exec": [ "flash.c3 arduino_uno build/firmware-uno.elf" ]
  }
}
```

The `script-dir` depends on how you get the library:

- As a directory (git submodule, a copy, or an unpacked archive): the path to
  its `scripts/` directory, as above.
- As the zipped `embedded.c3l` from a release or `c3c fetch`: c3c unpacks it
  while building the firmware target, so use
  `build/unpacked_c3l/embedded.c3l/scripts` (with the default `build-dir`).

The script finds `manifest.json` next to its own directory. The board name is
the key under `vendor.embedded.boards`: `arduino_uno` or `esp32c3_supermini`.

To flash a debug build, add a second prepare target that depends on the
`_debug` target and passes its ELF.

Without a project target, run the script directly:

```sh
c3c compile-run path/to/embedded.c3l/scripts/flash.c3 -- arduino_uno build/firmware-uno.elf
```

## How it works

c3c runs a target's `exec` steps before it compiles that target, never after.
A flash step on the firmware target would therefore run before the ELF exists,
or flash the previous build. A `prepare` target compiles nothing: c3c first
builds everything in its `depends-on` list, then runs its `exec` steps, which
gives the right order.

c3c captures a script's standard output and prints it only when the script
ends (and keeps just the first 2 KB). The script therefore sends avrdude's and
esptool's output to standard error, where it appears live. On Windows it goes
to standard output instead.

When an `exec` script fails, c3c leaves its compiled copy (`__c3exec__`) in
the working directory. It is in `.gitignore` and can be deleted.

## Sizes

`scripts/size.c3` prints flash and RAM use against the MCU's limits from the
same manifest:

```sh
c3c compile-run scripts/size.c3 -- arduino_uno examples/*/build/*-arduino-uno.elf
```

`--markdown` prints a table instead. CI adds it to each job's summary, and
the nightly release attaches the report for all examples.
