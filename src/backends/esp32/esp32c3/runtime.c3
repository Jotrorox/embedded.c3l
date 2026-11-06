module runtime @private;

fn void* memset(void* dest, int value, usz n) @export("memset")
{
	char* p = (char*)dest;
	for (usz i = 0; i < n; i++) p[i] = (char)value;
	return dest;
}

fn int __mulsi3(int a, int b) @export("__mulsi3")
{
	uint ua = (uint)a;
	uint ub = (uint)b;
	uint res = 0;
	while (ub != 0)
	{
		if (ub & 1) res += ua;
		ua <<= 1;
		ub >>= 1;
	}
	return (int)res;
}

fn uint __udivsi3(uint a, uint b) @export("__udivsi3")
{
	uint res = 0;
	uint bit = 1;
	while (b <= a && b)
	{
		b <<= 1;
		bit <<= 1;
	}
	while (bit)
	{
		if (a >= b)
		{
			a -= b;
			res |= bit;
		}
		b >>= 1;
		bit >>= 1;
	}
	return res;
}

fn uint __umodsi3(uint a, uint b) @export("__umodsi3")
{
	uint bit = 1;
	while (b <= a && b)
	{
		b <<= 1;
		bit <<= 1;
	}
	while (bit)
	{
		if (a >= b)
		{
			a -= b;
		}
		b >>= 1;
		bit >>= 1;
	}
	return a;
}

// 64-bit shifts by a variable amount. RV32 has no 64-bit registers, so LLVM
// calls these compiler-rt helpers; they are built from 32-bit halves here.
fn ulong __lshrdi3(ulong a, int b) @export("__lshrdi3")
{
	uint lo = (uint)a;
	uint hi = (uint)(a >> 32);
	b &= 63;
	if (b == 0) return a;
	if (b >= 32) return (ulong)(hi >> (b - 32));
	return (ulong)(hi >> b) << 32 | (ulong)((lo >> b) | (hi << (32 - b)));
}

fn ulong __ashldi3(ulong a, int b) @export("__ashldi3")
{
	uint lo = (uint)a;
	uint hi = (uint)(a >> 32);
	b &= 63;
	if (b == 0) return a;
	if (b >= 32) return (ulong)(lo << (b - 32)) << 32;
	return (ulong)((hi << b) | (lo >> (32 - b))) << 32 | (ulong)(lo << b);
}

fn long __ashrdi3(long a, int b) @export("__ashrdi3")
{
	int hi = (int)(a >> 32);
	uint lo = (uint)a;
	b &= 63;
	if (b == 0) return a;
	if (b >= 32) return (long)(hi >> (b - 32));
	return (long)(hi >> b) << 32 | (long)(ulong)((lo >> b) | ((uint)hi << (32 - b)));
}

// 64-bit division helpers (compiler-rt names). Plain shift-and-subtract:
// small, and fast enough for the occasional 64-bit division in setup code.
fn ulong udivmod64(ulong num, ulong den, ulong* rem) @local {
    if (den == 0) {
        *rem = num;
        return 0xFFFF_FFFF_FFFF_FFFF;
    }
    ulong quot = 0;
    ulong r = 0;
    for (int bit = 63; bit >= 0; bit--) {
        r = (r << 1) | ((num >> bit) & 1);
        if (r >= den) {
            r -= den;
            quot |= (ulong)1 << bit;
        }
    }
    *rem = r;
    return quot;
}

fn ulong __udivdi3(ulong a, ulong b) @export("__udivdi3") {
    ulong rem;
    return udivmod64(a, b, &rem);
}

fn ulong __umoddi3(ulong a, ulong b) @export("__umoddi3") {
    ulong rem;
    udivmod64(a, b, &rem);
    return rem;
}

fn long __divdi3(long a, long b) @export("__divdi3") {
    bool negative = (a < 0) != (b < 0);
    ulong rem;
    ulong q = udivmod64(a < 0 ? ~(ulong)a + 1 : (ulong)a, b < 0 ? ~(ulong)b + 1 : (ulong)b, &rem);
    return negative ? (long)(~q + 1) : (long)q;
}

fn long __moddi3(long a, long b) @export("__moddi3") {
    ulong rem;
    udivmod64(a < 0 ? ~(ulong)a + 1 : (ulong)a, b < 0 ? ~(ulong)b + 1 : (ulong)b, &rem);
    return a < 0 ? (long)(~rem + 1) : (long)rem;
}
