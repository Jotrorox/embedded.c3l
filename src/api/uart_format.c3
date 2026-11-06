module embedded::uart;

import embedded::time;

// Helpers shared by every backend, built on the backend's `Uart` methods.
// They are deliberately small: numbers in decimal or hex, no format strings.

fn char? Uart.read_byte(self, time::Duration timeout) {
    time::Instant deadline = time::deadline_after(timeout);
    while (true) {
        char? byte = self.try_read();
        if (catch err = byte) {
            if (err != NO_DATA) return err~;
            if (time::has_elapsed(deadline)) return TIMEOUT~;
            continue;
        }
        return byte;
    }
}

fn void Uart.write_line(self, char[] bytes) {
    self.write(bytes);
    self.write("\r\n");
}

// Quotient and remainder of a 64-bit value by 10 in one long-division pass,
// instead of the two runtime calls `%` and `/` would make. Only used for
// values above 32 bits, which are rare.
fn ulong div10_u64(ulong value, char* remainder) @local {
    ulong quotient = 0;
    uint rest = 0;
    for (int bit = 63; bit >= 0; bit--) {
        rest = (rest << 1) | (uint)((value >> bit) & 1);
        if (rest >= 10) {
            rest -= 10;
            quotient |= (ulong)1 << bit;
        }
    }
    *remainder = (char)rest;
    return quotient;
}

fn void Uart.write_uint(self, ulong value) {
    char[20] digits;
    usz count = 0;
    do {
        char digit;
        if (value <= 0xFFFF_FFFF) {
            uint small = (uint)value;
            digit = (char)(small % 10);
            value = small / 10;
        } else {
            value = div10_u64(value, &digit);
        }
        digits[count++] = '0' + digit;
    } while (value != 0);
    while (count > 0) self.write_byte(digits[--count]);
}

fn void Uart.write_int(self, long value) {
    if (value < 0) {
        self.write_byte('-');
        // Negate in unsigned arithmetic so the most negative value works.
        self.write_uint(~(ulong)value + 1);
        return;
    }
    self.write_uint((ulong)value);
}

// Writes `value` in upper-case hex, zero-padded to `min_digits`, without a
// "0x" prefix.
fn void Uart.write_hex(self, ulong value, char min_digits = 1) {
    char count = 16;
    while (count > 1 && count > min_digits && (value >> ((count - 1) * 4)) == 0) count--;
    while (count > 0) {
        count--;
        char nibble = (char)((value >> (count * 4)) & 0xF);
        self.write_byte(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
    }
}
