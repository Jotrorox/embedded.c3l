module embedded_size;

import std::io, std::encoding::json, std::collections::object;

// Prints how much flash and RAM firmware images use, against the limits of
// the board's MCU in the library's manifest.json (vendor.embedded).
//
//     c3c compile-run scripts/size.c3 -- [--markdown] <board> <firmware.elf>...
//
// text is every read-only section (code and constants), data the
// initialised writable sections, bss the zeroed ones (including .noinit).
// Read-only sections without contents are skipped: the ESP32-C3 script uses
// one (.dram_dummy) to keep data clear of the code, which sits in the same
// SRAM, and it would otherwise be counted twice (`size` counts it as text).
// Flash holds text + data. RAM holds
// data + bss, plus text on MCUs whose image runs from RAM (the ESP32-C3 build
// has no flash mapping yet). The stack reserve from the linker script is not
// included; the link already fails when it does not fit.
//
// Exits with 1 when an image does not fit, or cannot be read.

faultdef USAGE, BAD_MANIFEST, BAD_ELF;

struct Limits {
    String board_name;
    String mcu;
    ulong flash_bytes;
    ulong ram_bytes;
    bool runs_from_ram;
}

struct Sizes {
    ulong text;
    ulong data;
    ulong bss;
}

fn int main(String[] args) {
    bool markdown;
    String manifest_path = $$FILEPATH.path_tdirname()!!.tconcat("/../manifest.json");
    String board;
    String[] elfs = mem::talloc_array(String, args.len);
    int elf_count;
    for (sz i = 1; i < args.len; i++) {
        String arg = args[i];
        switch {
            case arg == "--markdown":
                markdown = true;
            case arg == "--manifest" && i + 1 < args.len:
                manifest_path = args[++i];
            case arg.starts_with("-"):
                usage();
                return 2;
            case !board:
                board = arg;
            default:
                elfs[elf_count++] = arg;
        }
    }
    if (!board || !elf_count) {
        usage();
        return 2;
    }
    Limits? limits = load_limits(manifest_path, board);
    if (catch limits) return 1;

    bool ok = true;
    print_header(&limits, markdown);
    foreach (elf : elfs[:elf_count]) {
        Sizes? sizes = read_sizes(elf);
        if (catch sizes) {
            io::eprintfn("size: cannot read '%s' as a 32-bit little-endian ELF file.", elf);
            ok = false;
            continue;
        }
        if (!print_row(&limits, elf, sizes, markdown)) ok = false;
    }
    return ok ? 0 : 1;
}

fn void usage() {
    io::eprintn("usage: size.c3 [--markdown] [--manifest <path>] <board> <firmware.elf>...");
}

fn Limits? load_limits(String manifest_path, String board) {
    char[]? text = file::load_temp(manifest_path);
    if (catch text) {
        io::eprintfn("size: cannot read '%s'.", manifest_path);
        return BAD_MANIFEST~;
    }
    Object*? vendor = json::tparse((String)text).get("vendor").get("embedded");
    if (catch vendor) {
        io::eprintfn("size: '%s' has no vendor.embedded block.", manifest_path);
        return BAD_MANIFEST~;
    }
    Object*? board_info = vendor.get("boards").get(board);
    if (catch board_info) {
        io::eprintfn("size: unknown board '%s'.", board);
        return BAD_MANIFEST~;
    }
    String? mcu = board_info.get_string("mcu");
    Object*? mcu_info = vendor.get("mcus").get(mcu);
    if (catch mcu_info) {
        io::eprintfn("size: board '%s' names an unknown MCU.", board);
        return BAD_MANIFEST~;
    }
    return {
        .board_name = board_info.get_string("name") ?? board,
        .mcu = mcu!!,
        .flash_bytes = (ulong)mcu_info.get_long("flash-bytes") ?? 0,
        .ram_bytes = (ulong)mcu_info.get_long("ram-bytes") ?? 0,
        .runs_from_ram = mcu_info.get_bool("runs-from-ram") ?? false,
    };
}

// ---------------------------------------------------------------------------
// ELF32 section headers.

const uint SHT_NOBITS = 8;
const uint SHF_WRITE = 1;
const uint SHF_ALLOC = 2;

fn uint u16_at(char[] b, ulong at) @inline => (uint)b[at] | (uint)b[at + 1] << 8;
fn uint u32_at(char[] b, ulong at) @inline => u16_at(b, at) | u16_at(b, at + 2) << 16;

fn Sizes? read_sizes(String path) {
    char[] elf = file::load_temp(path)!;
    if (elf.len < 52 || elf[0:4] != "\x7fELF" || elf[4] != 1 || elf[5] != 1) return BAD_ELF~;
    ulong shoff = u32_at(elf, 0x20);
    ulong shentsize = u16_at(elf, 0x2E);
    ulong shnum = u16_at(elf, 0x30);
    if (shentsize < 40 || shoff + shnum * shentsize > elf.len) return BAD_ELF~;
    Sizes sizes;
    for (ulong i = 0; i < shnum; i++) {
        ulong header = shoff + i * shentsize;
        uint type = u32_at(elf, header + 4);
        uint flags = u32_at(elf, header + 8);
        ulong size = u32_at(elf, header + 20);
        if (!(flags & SHF_ALLOC)) continue;
        if (type == SHT_NOBITS) {
            if (flags & SHF_WRITE) sizes.bss += size;
        } else if (flags & SHF_WRITE) {
            sizes.data += size;
        } else {
            sizes.text += size;
        }
    }
    return sizes;
}

// ---------------------------------------------------------------------------
// Output.

fn void print_header(Limits* limits, bool markdown) {
    if (markdown) {
        io::printfn("### %s (%s: %d KB flash, %d KB RAM)", limits.board_name, limits.mcu, limits.flash_bytes / 1024, limits.ram_bytes / 1024);
        io::printn();
        io::printn("| Firmware | text | data | bss | Flash | RAM |");
        io::printn("|---|---:|---:|---:|---:|---:|");
        return;
    }
    io::printfn("%s (%s: %d B flash, %d B RAM)", limits.board_name, limits.mcu, limits.flash_bytes, limits.ram_bytes);
    io::printfn("  %-36s %7s %7s %7s %16s %16s", "firmware", "text", "data", "bss", "flash", "RAM");
}

fn bool print_row(Limits* limits, String path, Sizes sizes, bool markdown) {
    ulong flash = sizes.text + sizes.data;
    ulong ram = sizes.data + sizes.bss + (limits.runs_from_ram ? sizes.text : 0);
    String name = path.file_tbasename() ?? path;
    if (name.ends_with(".elf")) name = name[:^4];
    String flash_cell = usage_cell(flash, limits.flash_bytes);
    String ram_cell = usage_cell(ram, limits.ram_bytes);
    if (markdown) {
        io::printfn("| %s | %d | %d | %d | %s | %s |", name, sizes.text, sizes.data, sizes.bss, flash_cell, ram_cell);
    } else {
        io::printfn("  %-36s %7d %7d %7d %16s %16s", name, sizes.text, sizes.data, sizes.bss, flash_cell, ram_cell);
    }
    bool fits = (!limits.flash_bytes || flash <= limits.flash_bytes) && (!limits.ram_bytes || ram <= limits.ram_bytes);
    if (!fits) io::eprintfn("size: %s does not fit the %s.", name, limits.mcu);
    return fits;
}

fn String usage_cell(ulong used, ulong limit) {
    if (!limit) return string::tformat("%d", used);
    // One decimal without floating-point formatting.
    ulong permille = (used * 1000 + limit / 2) / limit;
    return string::tformat("%d (%d.%d%%)", used, permille / 10, permille % 10);
}
