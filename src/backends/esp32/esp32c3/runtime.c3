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
