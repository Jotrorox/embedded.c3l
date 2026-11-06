module embedded::rt::avr @private @feat(BACKEND_AVR);

// AVR-only arithmetic helpers. avr-gcc's libgcc ABI is not compiler-rt's:
// LLVM's AVR backend calls __mulqi3/__mulhi3 and, for both `/` and `%`, the
// combined __[u]divmod{qi,hi,si}4 helpers. Those return the quotient in the
// low half of the return registers and the remainder in the high half:
//
//   __udivmodqi4  quotient r24,      remainder r25      (ushort return)
//   __udivmodhi4  quotient r22:r23,  remainder r24:r25  (uint return)
//   __udivmodsi4  quotient r18..r21, remainder r22..r25 (ulong return)
//
// The generic 32- and 64-bit helpers in this directory cover the rest.

// Products: the low bits are the same for signed and unsigned operands, so
// one shift-and-add loop serves both. LLVM also uses these for `%`, which it
// lowers to a - (a / b) * b.

fn ichar __mulqi3(ichar a, ichar b) @weak @export("__mulqi3") {
    char ua = (char)a;
    char ub = (char)b;
    char ur = 0;
    while (ub != 0) {
        if (ub & 1) ur += ua;
        ua <<= 1;
        ub >>= 1;
    }
    return (ichar)ur;
}

fn short __mulhi3(short a, short b) @weak @export("__mulhi3") {
    ushort ua = (ushort)a;
    ushort ub = (ushort)b;
    ushort ur = 0;
    while (ub != 0) {
        if (ub & 1) ur += ua;
        ua <<= 1;
        ub >>= 1;
    }
    return (short)ur;
}

// Division: shift-and-subtract. Dividing by zero gives an all-ones quotient
// and the dividend as remainder, like libgcc. Signed results truncate toward
// zero, and the remainder takes the sign of the dividend.

fn ushort __udivmodqi4(char num, char den) @weak @export("__udivmodqi4") {
    char quot = 0;
    char rem = 0;
    for (int i = 7; i >= 0; i--) {
        rem = (char)(rem << 1 | ((num >> i) & 1));
        if (rem >= den) {
            rem -= den;
            quot |= (char)(1 << i);
        }
    }
    return (ushort)rem << 8 | quot;
}

fn ushort __divmodqi4(ichar num, ichar den) @weak @export("__divmodqi4") {
    ushort r = __udivmodqi4((char)(num < 0 ? -num : num), (char)(den < 0 ? -den : den));
    char quot = (char)r;
    char rem = (char)(r >> 8);
    if ((num < 0) != (den < 0)) quot = (char)-quot;
    if (num < 0) rem = (char)-rem;
    return (ushort)rem << 8 | quot;
}

fn uint __udivmodhi4(ushort num, ushort den) @weak @export("__udivmodhi4") {
    ushort quot = 0;
    ushort rem = 0;
    for (int i = 15; i >= 0; i--) {
        rem = (ushort)(rem << 1 | ((num >> i) & 1));
        if (rem >= den) {
            rem -= den;
            quot |= (ushort)(1 << i);
        }
    }
    return (uint)rem << 16 | quot;
}

fn uint __divmodhi4(short num, short den) @weak @export("__divmodhi4") {
    uint r = __udivmodhi4((ushort)(num < 0 ? -num : num), (ushort)(den < 0 ? -den : den));
    ushort quot = (ushort)r;
    ushort rem = (ushort)(r >> 16);
    if ((num < 0) != (den < 0)) quot = (ushort)-quot;
    if (num < 0) rem = (ushort)-rem;
    return (uint)rem << 16 | quot;
}

fn ulong __udivmodsi4(uint num, uint den) @weak @export("__udivmodsi4") {
    uint quot = 0;
    uint rem = 0;
    for (int i = 31; i >= 0; i--) {
        rem = rem << 1 | ((num >> i) & 1);
        if (rem >= den) {
            rem -= den;
            quot |= (uint)1 << i;
        }
    }
    return (ulong)rem << 32 | quot;
}

fn ulong __divmodsi4(int num, int den) @weak @export("__divmodsi4") {
    ulong r = __udivmodsi4(num < 0 ? ~(uint)num + 1 : (uint)num, den < 0 ? ~(uint)den + 1 : (uint)den);
    uint quot = (uint)r;
    uint rem = (uint)(r >> 32);
    if ((num < 0) != (den < 0)) quot = ~quot + 1;
    if (num < 0) rem = ~rem + 1;
    return (ulong)rem << 32 | quot;
}
