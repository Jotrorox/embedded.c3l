module embedded::rt @private;

// 64-bit integer helpers under their compiler-rt names. Neither core has
// 64-bit registers, so LLVM calls these for `ulong` multiply and divide
// (time::Duration arithmetic, baud and clock divider maths).

// The low 64 bits of a product are the same for signed and unsigned operands,
// so one shift-and-add loop serves both.
fn long __muldi3(long a, long b) @weak @export("__muldi3")
{
	ulong ua = (ulong)a;
	ulong ub = (ulong)b;
	ulong res = 0;
	while (ub != 0)
	{
		if (ub & 1) res += ua;
		ua <<= 1;
		ub >>= 1;
	}
	return (long)res;
}

// Plain shift-and-subtract: small, and fast enough for the occasional 64-bit
// division in setup code. Returns the quotient and stores the remainder.
fn ulong udivmod64(ulong num, ulong den, ulong* rem) @local
{
	if (den == 0)
	{
		*rem = num;
		return 0xFFFF_FFFF_FFFF_FFFF;
	}
	ulong quot = 0;
	ulong r = 0;
	for (int bit = 63; bit >= 0; bit--)
	{
		r = (r << 1) | ((num >> bit) & 1);
		if (r >= den)
		{
			r -= den;
			quot |= (ulong)1 << bit;
		}
	}
	*rem = r;
	return quot;
}

fn ulong __udivdi3(ulong a, ulong b) @weak @export("__udivdi3")
{
	ulong rem;
	return udivmod64(a, b, &rem);
}

fn ulong __umoddi3(ulong a, ulong b) @weak @export("__umoddi3")
{
	ulong rem;
	udivmod64(a, b, &rem);
	return rem;
}

fn long __divdi3(long a, long b) @weak @export("__divdi3")
{
	ulong rem;
	ulong q = udivmod64(a < 0 ? ~(ulong)a + 1 : (ulong)a, b < 0 ? ~(ulong)b + 1 : (ulong)b, &rem);
	return (a < 0) != (b < 0) ? (long)(~q + 1) : (long)q;
}

fn long __moddi3(long a, long b) @weak @export("__moddi3")
{
	ulong rem;
	udivmod64(a < 0 ? ~(ulong)a + 1 : (ulong)a, b < 0 ? ~(ulong)b + 1 : (ulong)b, &rem);
	return a < 0 ? (long)(~rem + 1) : (long)rem;
}
