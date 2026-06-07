module embedded::backends::avr::atmega328p::runtime @private;

// Signed 16-bit multiply.
fn short __mulhi3(short a, short b) @export("__mulhi3") {
    bool negative = (a < 0) != (b < 0);
    ushort ua = (ushort)(a < 0 ? -a : a);
    ushort ub = (ushort)(b < 0 ? -b : b);
    ushort ur = 0;

    while (ub != 0) {
        if (ub & 1) ur += ua;
        ua <<= 1;
        ub >>= 1;
    }

    short result = (short)ur;
    return negative ? -result : result;
}

// Signed 32-bit multiply.
fn int __mulsi3(int a, int b) @export("__mulsi3") {
    bool negative = (a < 0) != (b < 0);
    uint ua = (uint)(a < 0 ? -a : a);
    uint ub = (uint)(b < 0 ? -b : b);
    uint ur = 0;

    while (ub != 0) {
        if (ub & 1) ur += ua;
        ua <<= 1;
        ub >>= 1;
    }

    int result = (int)ur;
    return negative ? -result : result;
}

fn char __udivmodqi4(char num, char den) @export("__udivmodqi4") {
    char quot = 0;
    char rem = 0;
    for (int i = 7; i >= 0; i--) {
        rem = (char)(rem << 1);
        rem = (char)(rem | ((num >> i) & 1));
        if (rem >= den) {
            rem = (char)(rem - den);
            quot = (char)(quot | (1 << i));
        }
    }
    return quot;
}

fn ichar __divmodqi4(ichar num, ichar den) @export("__divmodqi4") {
    bool negative = (num < 0) != (den < 0);
    char unum = (char)(num < 0 ? -num : num);
    char uden = (char)(den < 0 ? -den : den);
    char uquot = __udivmodqi4(unum, uden);
    ichar quot = (ichar)uquot;
    return negative ? (ichar)(-quot) : quot;
}

fn char __udivqi4(char num, char den) @export("__udivqi4") {
    return __udivmodqi4(num, den);
}

fn ichar __divqi4(ichar num, ichar den) @export("__divqi4") {
    return __divmodqi4(num, den);
}

fn char __umodqi4(char num, char den) @export("__umodqi4") {
    char rem = 0;
    for (int i = 7; i >= 0; i--) {
        rem = (char)(rem << 1);
        rem = (char)(rem | ((num >> i) & 1));
        if (rem >= den) {
            rem = (char)(rem - den);
        }
    }
    return rem;
}

fn ichar __modqi4(ichar num, ichar den) @export("__modqi4") {
    bool negative = num < 0;
    char unum = (char)(num < 0 ? -num : num);
    char uden = (char)(den < 0 ? -den : den);
    char rem = __umodqi4(unum, uden);
    return negative ? (ichar)(-rem) : (ichar)rem;
}

// Returns (quotient << 16) | remainder so that r24:r25 = quot and r22:r23 = rem.
fn uint __udivmodhi4(ushort num, ushort den) @export("__udivmodhi4") {
    ushort quot = 0;
    ushort rem = 0;
    for (int i = 15; i >= 0; i--) {
        rem = (ushort)(rem << 1);
        rem = (ushort)(rem | ((num >> i) & 1));
        if (rem >= den) {
            rem = (ushort)(rem - den);
            quot = (ushort)(quot | (1 << i));
        }
    }
    return ((uint)quot << 16) | (uint)rem;
}

// Returns (quotient << 16) | remainder so that r24:r25 = quot and r22:r23 = rem.
fn int __divmodhi4(short num, short den) @export("__divmodhi4") {
    bool negative = (num < 0) != (den < 0);
    ushort unum = (ushort)(num < 0 ? -num : num);
    ushort uden = (ushort)(den < 0 ? -den : den);
    ushort quot = 0;
    ushort rem = 0;
    for (int i = 15; i >= 0; i--) {
        rem = (ushort)(rem << 1);
        rem = (ushort)(rem | ((unum >> i) & 1));
        if (rem >= uden) {
            rem = (ushort)(rem - uden);
            quot = (ushort)(quot | (1 << i));
        }
    }
    short squot = (short)quot;
    short srem = (short)rem;
    if (negative) squot = (short)(-squot);
    if (num < 0) srem = (short)(-srem);
    return (uint)((int)squot << 16) | (uint)(ushort)srem;
}

fn ushort __udivhi4(ushort num, ushort den) @export("__udivhi4") {
    return (ushort)(__udivmodhi4(num, den) >> 16);
}

fn short __divhi4(short num, short den) @export("__divhi4") {
    return (short)(__divmodhi4(num, den) >> 16);
}

fn ushort __umodhi4(ushort num, ushort den) @export("__umodhi4") {
    return (ushort)__udivmodhi4(num, den);
}

fn short __modhi4(short num, short den) @export("__modhi4") {
    return (short)__divmodhi4(num, den);
}

// Returns (quotient << 32) | remainder.
fn ulong __udivmodsi4(uint num, uint den) @export("__udivmodsi4") {
    uint quot = 0;
    uint rem = 0;
    for (int i = 31; i >= 0; i--) {
        rem = rem << 1;
        rem = rem | ((num >> i) & 1);
        if (rem >= den) {
            rem = rem - den;
            quot = quot | ((uint)1 << (uint)i);
        }
    }
    return ((ulong)quot << 32) | (ulong)rem;
}

// Returns (quotient << 32) | remainder.
fn long __divmodsi4(int num, int den) @export("__divmodsi4") {
    bool negative = (num < 0) != (den < 0);
    uint unum = (uint)(num < 0 ? -num : num);
    uint uden = (uint)(den < 0 ? -den : den);
    uint quot = 0;
    uint rem = 0;
    for (int i = 31; i >= 0; i--) {
        rem = rem << 1;
        rem = rem | ((unum >> i) & 1);
        if (rem >= uden) {
            rem = rem - uden;
            quot = quot | ((uint)1 << (uint)i);
        }
    }
    int squot = (int)quot;
    int srem = (int)rem;
    if (negative) squot = -squot;
    if (num < 0) srem = -srem;
    return (ulong)((long)squot << 32) | (ulong)(uint)srem;
}

fn uint __udivsi4(uint num, uint den) @export("__udivsi4") {
    return (uint)(__udivmodsi4(num, den) >> 32);
}

fn int __divsi4(int num, int den) @export("__divsi4") {
    return (int)(__divmodsi4(num, den) >> 32);
}

fn uint __umodsi4(uint num, uint den) @export("__umodsi4") {
    return (uint)__udivmodsi4(num, den);
}

fn int __modsi4(int num, int den) @export("__modsi4") {
    return (int)__divmodsi4(num, den);
}

fn void* memset(void* dest, int val, usz len) @export("memset") {
    char* d = (char*)dest;
    char v = (char)val;
    for (usz i = 0; i < len; i++) {
        d[i] = v;
    }
    return dest;
}

fn void* memcpy(void* dest, void* src, usz len) @export("memcpy") {
    char* d = (char*)dest;
    char* s = (char*)src;
    for (usz i = 0; i < len; i++) {
        d[i] = s[i];
    }
    return dest;
}
