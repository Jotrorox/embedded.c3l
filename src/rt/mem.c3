module embedded::rt @private;

// Freestanding replacements for the libc memory functions that LLVM emits
// calls to (struct copies, zero-initialisation, array assignment). Every
// definition here and in the other src/rt/ files is weak, so firmware can
// link a faster version instead, and section GC drops the unused ones.
//
// The loops are plain on purpose: LLVM does not turn a loop inside a
// function called memset/memcpy/memmove back into a call to itself.

fn void* memset(void* dest, int value, usz len) @weak @export("memset")
{
	char* d = (char*)dest;
	for (usz i = 0; i < len; i++) d[i] = (char)value;
	return dest;
}

fn void* memcpy(void* dest, void* src, usz len) @weak @export("memcpy")
{
	char* d = (char*)dest;
	char* s = (char*)src;
	for (usz i = 0; i < len; i++) d[i] = s[i];
	return dest;
}

fn void* memmove(void* dest, void* src, usz len) @weak @export("memmove")
{
	char* d = (char*)dest;
	char* s = (char*)src;
	if (d <= s)
	{
		for (usz i = 0; i < len; i++) d[i] = s[i];
	}
	else
	{
		for (usz i = len; i > 0; i--) d[i - 1] = s[i - 1];
	}
	return dest;
}
