module embedded::rt @private @feat(!BACKEND_AVR);

// 64-bit shifts by a variable amount, built from 32-bit halves. RV32 has no
// 64-bit registers, so LLVM calls these. The shift count is a C `int`, which
// is 16 bits on AVR; the AVR backend expands these shifts inline, so this
// file is left out there rather than given the wrong signature.

fn ulong __lshrdi3(ulong a, int b) @weak @export("__lshrdi3")
{
	uint lo = (uint)a;
	uint hi = (uint)(a >> 32);
	b &= 63;
	if (b == 0) return a;
	if (b >= 32) return (ulong)(hi >> (b - 32));
	return (ulong)(hi >> b) << 32 | (ulong)((lo >> b) | (hi << (32 - b)));
}

fn ulong __ashldi3(ulong a, int b) @weak @export("__ashldi3")
{
	uint lo = (uint)a;
	uint hi = (uint)(a >> 32);
	b &= 63;
	if (b == 0) return a;
	if (b >= 32) return (ulong)(lo << (b - 32)) << 32;
	return (ulong)((hi << b) | (lo >> (32 - b))) << 32 | (ulong)(lo << b);
}

fn long __ashrdi3(long a, int b) @weak @export("__ashrdi3")
{
	int hi = (int)(a >> 32);
	uint lo = (uint)a;
	b &= 63;
	if (b == 0) return a;
	if (b >= 32) return (long)(hi >> (b - 32));
	return (long)(hi >> b) << 32 | (long)(ulong)((lo >> b) | ((uint)hi << (32 - b)));
}
