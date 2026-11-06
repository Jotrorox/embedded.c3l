module embedded_flash;

import std::io, std::os, std::os::process, std::io::path, std::encoding::json, std::collections::object;

// Flashes a firmware ELF onto a board, using the flash settings in the
// library's manifest.json (vendor.embedded.boards.<board>.flash).
//
//     c3c compile-run scripts/flash.c3 -- <board> <firmware.elf> [options]
//
// or, from a project, as the `exec` step of a `prepare` target that
// `depends-on` the firmware target (see docs/flashing.md):
//
//     "flash-arduino-uno": {
//       "type": "prepare",
//       "depends-on": [ "blink-arduino-uno" ],
//       "exec": [ "<path to embedded.c3l>/scripts/flash.c3 arduino_uno build/blink-arduino-uno.elf" ]
//     }
//
//     c3c build flash-arduino-uno --trust=full
//
// Options:
//     --port <port>   serial port; default: $PORT, else the only port that
//                     matches the board's pattern for this OS
//     --dry-run       print the commands instead of running them (also
//                     with FLASH_DRY_RUN=1, for use under `exec`)
//     --manifest <p>  manifest.json to read (default: next to this script)
//
// Tools: avrdude 7.0 or newer for the Uno (it reads the ELF directly), and
// esptool (`esptool` or `esptool.py`) for the ESP32-C3.
//
// Under `exec`, c3c captures a script's standard output and shows it only
// when the script ends, so the flashing tools' output goes to standard error
// where it appears as it happens.

faultdef USAGE, BAD_MANIFEST, NO_PORT, AMBIGUOUS_PORT, NO_TOOL, TOOL_FAILED;

struct Options {
    String board;
    String elf;
    String port;
    String manifest;
    bool dry_run;
}

fn int main(String[] args) {
    Options opts;
    if (catch err = parse_args(args, &opts)) {
        if (err == USAGE) usage();
        return 2;
    }
    if (catch flash(&opts)) return 1;
    return 0;
}

fn void usage() {
    io::eprintn("usage: flash.c3 <board> <firmware.elf> [--port <port>] [--dry-run] [--manifest <path>]");
}

fn void? parse_args(String[] args, Options* opts) {
    String[2] positional;
    int count;
    for (sz i = 1; i < args.len; i++) {
        String arg = args[i];
        switch (arg) {
            case "--dry-run":
                opts.dry_run = true;
            case "--port":
            case "--manifest":
                if (i + 1 >= args.len) return USAGE~;
                if (arg == "--port") {
                    opts.port = args[++i];
                } else {
                    opts.manifest = args[++i];
                }
            case "-h":
            case "--help":
                return USAGE~;
            default:
                if (arg.starts_with("-") || count == 2) return USAGE~;
                positional[count++] = arg;
        }
    }
    if (count != 2) return USAGE~;
    if (try dry = env::tget_var("FLASH_DRY_RUN")) {
        if (dry.len && dry != "0") opts.dry_run = true;
    }
    opts.board = positional[0];
    opts.elf = positional[1];
    if (!opts.manifest) {
        opts.manifest = $$FILEPATH.path_tdirname()!!.tconcat("/../manifest.json");
    }
}

fn void? flash(Options* opts) {
    Object* settings = load_flash_settings(opts.manifest, opts.board)!;
    if (!file::exists(opts.elf)) {
        io::eprintfn("flash: '%s' does not exist; build the firmware target first.", opts.elf);
        return BAD_MANIFEST~;
    }
    String tool = settings.get_string("tool") ?? "";
    switch (tool) {
        case "avrdude": flash_avrdude(opts, settings)!;
        case "esptool": flash_esptool(opts, settings)!;
        default:
            io::eprintfn("flash: board '%s' names unknown flash tool '%s'.", opts.board, tool);
            return BAD_MANIFEST~;
    }
}

fn Object*? load_flash_settings(String manifest_path, String board) {
    char[]? text = file::load_temp(manifest_path);
    if (catch text) {
        io::eprintfn("flash: cannot read '%s'.", manifest_path);
        return BAD_MANIFEST~;
    }
    Object*? manifest = json::tparse((String)text);
    if (catch manifest) {
        io::eprintfn("flash: '%s' is not valid JSON.", manifest_path);
        return BAD_MANIFEST~;
    }
    Object*? boards = manifest.get("vendor").get("embedded").get("boards");
    if (catch boards) {
        io::eprintfn("flash: '%s' has no vendor.embedded.boards block.", manifest_path);
        return BAD_MANIFEST~;
    }
    Object*? settings = boards.get(board).get("flash");
    if (catch settings) {
        io::eprintf("flash: unknown board '%s'. Boards in %s:", board, manifest_path);
        foreach (key : boards.map.keys(tmem)) io::eprintf(" %s", key);
        io::eprintn();
        return BAD_MANIFEST~;
    }
    return settings;
}

// ---------------------------------------------------------------------------
// Tools.

fn void? flash_avrdude(Options* opts, Object* settings) {
    String avrdude = find_tool({ "avrdude" }, opts.dry_run)!;
    String? port = resolve_port(opts.port, settings, !opts.dry_run);
    if (opts.dry_run && @catch(port) == NO_PORT) port = "<port>";
    port!;
    String target = string::tformat("flash:w:%s:e", opts.elf);
    run(opts, {
        avrdude,
        "-p", settings.get_string("chip")!,
        "-c", settings.get_string("programmer")!,
        "-P", port,
        "-b", string::tformat("%d", settings.get_int("baud")!),
        "-D",
        "-U", target,
    })!;
}

fn void? flash_esptool(Options* opts, Object* settings) {
    String esptool = find_tool({ "esptool", "esptool.py" }, opts.dry_run)!;
    String chip = settings.get_string("chip")!;
    String mode = settings.get_string("flash-mode")!;
    String freq = settings.get_string("flash-freq")!;
    String size = settings.get_string("flash-size")!;
    String image = opts.elf.ends_with(".elf") ? opts.elf[:^4].tconcat(".bin") : opts.elf.tconcat(".bin");
    run(opts, {
        esptool, "--chip", chip, "elf2image",
        "--flash-mode", mode, "--flash-freq", freq, "--flash-size", size,
        "-o", image, opts.elf,
    })!;
    // esptool finds the port itself when none is given, so a missing port is
    // only an error when the pattern matches more than one.
    String? found = resolve_port(opts.port, settings, false);
    fault err = @catch(found);
    if (err && err != NO_PORT) return err~;
    String port = err ? "" : found!!;
    if (err) io::eprintn("flash: esptool will look for the port itself.");
    String[] args = { esptool, "--chip", chip };
    if (port.len) args = { esptool, "--chip", chip, "-p", port };
    String[] write = {
        "-b", string::tformat("%d", settings.get_int("baud")!),
        "write_flash", "--flash-mode", mode, "--flash-freq", freq, "--flash-size", size,
        settings.get_string("offset")!, image,
    };
    run(opts, concat(args, write))!;
}

fn String[] concat(String[] a, String[] b) {
    String[] result = mem::talloc_array(String, a.len + b.len);
    result[:a.len] = a[..];
    result[a.len:b.len] = b[..];
    return result;
}

// Runs `command` with its output on our standard error, so it shows up live
// under `exec`.
fn void? run(Options* opts, String[] command) {
    io::eprintf(opts.dry_run ? "would run:" : "flash:");
    foreach (part : command) io::eprintf(" %s", part);
    io::eprintn();
    if (opts.dry_run) return;
    $if env::POSIX:
        int? status = process::run(command, INHERIT_ENV, in: process::INHERIT, out: process::bind(2), err: process::INHERIT);
    $else
        int? status = process::run(command, INHERIT_ENV | INHERIT_STDIO);
    $endif
    if (catch status) {
        io::eprintfn("flash: could not start '%s'.", command[0]);
        return TOOL_FAILED~;
    }
    if (status != 0) {
        io::eprintfn("flash: '%s' failed with exit code %d.", command[0], status);
        return TOOL_FAILED~;
    }
}

// The first of `names` found on PATH, as a full path. A dry run that finds
// none prints the commands with the first name.
fn String? find_tool(String[] names, bool dry_run) {
    String path_var = env::tget_var("PATH") ?? "";
    String separator = env::WIN32 ? ";" : ":";
    foreach (name : names) {
        foreach (dir : path_var.tsplit(separator, skip_empty: true)) {
            String candidate = dir.tconcat("/").tconcat(name);
            if (file::exists(candidate)) return candidate;
            $if env::WIN32:
                if (file::exists(candidate.tconcat(".exe"))) return candidate.tconcat(".exe");
            $endif
        }
    }
    io::eprintf("flash: none of");
    foreach (name : names) io::eprintf(" '%s'", name);
    io::eprintn(" is on PATH.");
    if (dry_run) return names[0];
    return NO_TOOL~;
}

// --port, else $PORT, else the single match of the board's port pattern for
// this OS (for example /dev/cu.usbmodem* on macOS). Without a match the
// result is NO_PORT, which is only reported as an error when `required`.
fn String? resolve_port(String port, Object* settings, bool required) {
    if (port.len) return port;
    if (try from_env = env::tget_var("PORT")) {
        if (from_env.len) return from_env;
    }
    String os_name = env::DARWIN ? "macos" : env::WIN32 ? "windows" : "linux";
    String? pattern = settings.get("port").get_string(os_name);
    if (catch pattern) return no_port(required, "set PORT or pass --port");
    // Serial ports on Windows cannot be listed as files.
    if (env::WIN32 || !pattern.starts_with("/")) {
        return no_port(required, string::tformat("set PORT or pass --port (%s)", pattern));
    }
    String dir = pattern.path_tdirname()!!;
    String mask = pattern[dir.len + 1..];
    PathList? entries = path::ls(tmem, path::tnew(dir)!!, mask: mask);
    if (catch entries) {
        io::eprintfn("flash: cannot list %s.", dir);
        return NO_PORT~;
    }
    if (entries.len() == 1) return dir.tconcat("/").tconcat((String)entries[0]);
    if (entries.len() == 0) {
        return no_port(required, string::tformat("no port matches %s; is the board connected? Otherwise set PORT", pattern));
    }
    io::eprintf("flash: several ports match %s:", pattern);
    foreach (entry : entries) io::eprintf(" %s/%s", dir, (String)entry);
    io::eprintn(". Set PORT or pass --port.");
    return AMBIGUOUS_PORT~;
}

fn String? no_port(bool required, String reason) {
    io::eprintfn(required ? "flash: %s." : "flash: note: %s.", reason);
    return NO_PORT~;
}
