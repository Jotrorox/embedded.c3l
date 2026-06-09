module embedded::uart;

const char TYPEKIND_CONSTDEF = 9;
const char TYPEKIND_FUNC = 13;
const char TYPEKIND_TYPEDEF = 18;
const char TYPEKIND_POINTER = 19;

const uint USB_SERIAL_JTAG_BASE = 0x6004_3000;
const uint USB_SERIAL_JTAG_EP1 = USB_SERIAL_JTAG_BASE + 0x0000;
const uint USB_SERIAL_JTAG_EP1_CONF = USB_SERIAL_JTAG_BASE + 0x0004;
const uint USB_SERIAL_JTAG_WR_DONE = 1u << 0;
const uint USB_SERIAL_JTAG_SERIAL_IN_EP_DATA_FREE = 1u << 1;
const uint USB_SERIAL_JTAG_SERIAL_OUT_EP_DATA_AVAIL = 1u << 2;

bool initialized @local = false;

fn void reg_write(uint addr, uint value) {
    @volatile_store(*(uint*)addr, value);
}

fn uint reg_read(uint addr) {
    return @volatile_load(*(uint*)addr);
}

fn void begin(uint baud) {
    if (baud == 0) baud = 115200;

    // UART0 is enabled/configured by the ESP32-C3 ROM boot path. Leave the
    // ROM's USB-serial/JTAG console routing untouched; this keeps output on
    // the same /dev/ttyACM* port used for flashing on common DevKit boards.
    initialized = true;
}

fn bool can_read() {
    if (!initialized) begin(115200);
    return (reg_read(USB_SERIAL_JTAG_EP1_CONF) & USB_SERIAL_JTAG_SERIAL_OUT_EP_DATA_AVAIL) != 0;
}

fn char read() {
    if (!initialized) begin(115200);
    while (!can_read()) {}
    return (char)(reg_read(USB_SERIAL_JTAG_EP1) & 0xFF);
}

fn void write_byte(char c) {
    if (!initialized) begin(115200);
    while ((reg_read(USB_SERIAL_JTAG_EP1_CONF) & USB_SERIAL_JTAG_SERIAL_IN_EP_DATA_FREE) == 0) {}
    reg_write(USB_SERIAL_JTAG_EP1, (uint)c & 0xFF);
    reg_write(USB_SERIAL_JTAG_EP1_CONF, USB_SERIAL_JTAG_WR_DONE);
}

fn void print(String s) {
    if (!initialized) begin(115200);
    for (usz i = 0; i < s.len && s[i] != 0; i++) {
        write_byte(s[i]);
    }
}

fn void printn(String s) {
    print(s);
    write_byte('\r');
    write_byte('\n');
}

fn void write_uint(uint value, uint base, bool upper) {
    char[32] buf;
    usz i = 0;
    if (value == 0) {
        write_byte('0');
        return;
    }
    while (value != 0) {
        uint digit = (uint)(value % base);
        buf[i++] = (char)(digit < 10 ? '0' + digit : (upper ? 'A' : 'a') + digit - 10);
        value /= base;
    }
    while (i > 0) write_byte(buf[--i]);
}

fn bool any_to_uint(any arg, uint* value, bool* neg) {
    *neg = false;
    switch (arg.type.kind) {
        case TYPEKIND_POINTER:
        case TYPEKIND_FUNC:
            *value = (uint)(uptr)*(void**)arg.ptr;
            return true;
        default:
            break;
    }
    switch (arg.type) {
        case bool: *value = *(bool*)arg.ptr ? 1 : 0; return true;
        case char: *value = *(char*)arg.ptr; return true;
        case ichar:
            ichar v = *(ichar*)arg.ptr; *neg = v < 0; *value = *neg ? (uint)(-v) : (uint)v; return true;
        case short:
            short v = *(short*)arg.ptr; *neg = v < 0; *value = *neg ? (uint)(-v) : (uint)v; return true;
        case int:
            int v = *(int*)arg.ptr; *neg = v < 0; *value = *neg ? (uint)(-v) : (uint)v; return true;
        case long:
            long v = *(long*)arg.ptr; *neg = v < 0; *value = *neg ? (uint)(-v) : (uint)v; return true;
        case int128:
            int128 v = *(int128*)arg.ptr; *neg = v < 0; *value = (uint)v; return true;
        case ushort: *value = *(ushort*)arg.ptr; return true;
        case uint: *value = *(uint*)arg.ptr; return true;
        case ulong: *value = (uint)*(ulong*)arg.ptr; return true;
        case uint128: *value = (uint)*(uint128*)arg.ptr; return true;
        default: return false;
    }
}

fn void print_any_string(any arg) {
    if (arg.type == String) {
        print(*(String*)arg.ptr);
        return;
    }
    if (arg.type == char[]) {
        print((String)*(char[]*)arg.ptr);
        return;
    }
    if (arg.type.kind == TYPEKIND_POINTER && arg.type.inner == char) {
        char* s = *(char**)arg.ptr;
        if (s == null) { print("(null)"); return; }
        while (*s != 0) write_byte(*s++);
        return;
    }
    uint value;
    bool neg;
    if (any_to_uint(arg, &value, &neg)) {
        if (neg) write_byte('-');
        write_uint(value, 10, false);
    } else {
        print("<unsupported>");
    }
}

fn void vprintf(String format, any[] args) {
    usz argi = 0;
    for (usz i = 0; i < format.len; i++) {
        char c = format[i];
        if (c == 0) break;
        if (c != '%') { write_byte(c); continue; }
        if (++i >= format.len) { write_byte('%'); break; }
        c = format[i];
        if (c == '%') { write_byte('%'); continue; }
        while (c == '0' || c == '-' || c == '+' || c == ' ' || c == '#') {
            if (++i >= format.len) return;
            c = format[i];
        }
        while (c >= '0' && c <= '9') {
            if (++i >= format.len) return;
            c = format[i];
        }
        if (c == '.') {
            if (++i >= format.len) return;
            c = format[i];
            while (c >= '0' && c <= '9') {
                if (++i >= format.len) return;
                c = format[i];
            }
        }
        if (argi >= args.len) { print("<missing>"); continue; }
        any arg = args[argi++];
        uint value;
        bool neg;
        if (c == 'c') {
            if (any_to_uint(arg, &value, &neg)) { write_byte((char)value); } else { print("<unsupported>"); }
        } else if (c == 's') {
            print_any_string(arg);
        } else if (c == 'd' || c == 'i') {
            if (any_to_uint(arg, &value, &neg)) { if (neg) write_byte('-'); write_uint(value, 10, false); } else { print("<unsupported>"); }
        } else if (c == 'u') {
            if (any_to_uint(arg, &value, &neg)) { write_uint(value, 10, false); } else { print("<unsupported>"); }
        } else if (c == 'x') {
            if (any_to_uint(arg, &value, &neg)) { write_uint(value, 16, false); } else { print("<unsupported>"); }
        } else if (c == 'X') {
            if (any_to_uint(arg, &value, &neg)) { write_uint(value, 16, true); } else { print("<unsupported>"); }
        } else if (c == 'o') {
            if (any_to_uint(arg, &value, &neg)) { write_uint(value, 8, false); } else { print("<unsupported>"); }
        } else if (c == 'p') {
            print("0x");
            if (any_to_uint(arg, &value, &neg)) { write_uint(value, 16, false); } else { print("<unsupported>"); }
        } else {
            write_byte('%'); write_byte(c);
        }
    }
}

fn void printf(String format, args...) @format(0) {
    vprintf(format, args);
}

fn void printfn(String format, args...) @format(0) {
    vprintf(format, args);
    write_byte('\r');
    write_byte('\n');
}
