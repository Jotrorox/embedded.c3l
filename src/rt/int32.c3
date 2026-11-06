module embedded::rt @private;

// 32-bit integer helpers under their compiler-rt names, for cores without a
// hardware multiplier or divider. AVR uses its own division ABI (avr.c3) and
// only takes __mulsi3 from here.

// The low 32 bits of a product are the same for signed and unsigned operands,
// so one shift-and-add loop serves both.
fn int __mulsi3(int a, int b) @weak @export("__mulsi3")
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

// Shift-and-subtract. Returns the quotient and stores the remainder.
fn uint udivmod32(uint num, uint den, uint* rem) @local
{
	uint quot = 0;
	uint bit = 1;
	while (den <= num && den != 0 && !(den & 0x8000_0000))
	{
		den <<= 1;
		bit <<= 1;
	}
	while (bit)
	{
		if (num >= den)
		{
			num -= den;
			quot |= bit;
		}
		den >>= 1;
		bit >>= 1;
	}
	*rem = num;
	return quot;
}

fn uint __udivsi3(uint a, uint b) @weak @export("__udivsi3")
{
	uint rem;
	return udivmod32(a, b, &rem);
}

fn uint __umodsi3(uint a, uint b) @weak @export("__umodsi3")
{
	uint rem;
	udivmod32(a, b, &rem);
	return rem;
}

fn int __divsi3(int a, int b) @weak @export("__divsi3")
{
	uint rem;
	uint q = udivmod32(a < 0 ? ~(uint)a + 1 : (uint)a, b < 0 ? ~(uint)b + 1 : (uint)b, &rem);
	return (a < 0) != (b < 0) ? (int)(~q + 1) : (int)q;
}

fn int __modsi3(int a, int b) @weak @export("__modsi3")
{
	uint rem;
	udivmod32(a < 0 ? ~(uint)a + 1 : (uint)a, b < 0 ? ~(uint)b + 1 : (uint)b, &rem);
	return a < 0 ? (int)(~rem + 1) : (int)rem;
}
