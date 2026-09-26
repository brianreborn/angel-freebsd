/*
 * LD_PRELOAD CPUID advertise for the same bits the kernel module would
 * report if user-mode CPUID trapped: SSSE3, SSE4.1, SSE4.2, OR'd onto
 * whatever the silicon already returns. Every other leaf and bit is
 * the real CPUID result.
 *
 * This file is baseline amd64 only (no SSSE3/SSE4 machine code).
 * It does not translate opcodes. It is not on the kernel #UD path.
 *
 * Rocky 9 glibc does not call a PLT symbol to read CPUID. ld.so runs
 * CPUID inside init_cpu_features(), then _dl_check_isa_level() rejects
 * the main executable's GNU_PROPERTY_X86_ISA_1_NEEDED note, and that
 * happens before LD_PRELOAD objects are mapped. A constructor here is
 * too late for that particular check. What this library can do:
 *   - interpose __get_cpuid / __get_cpuid_count (GCC/clang helpers and
 *     any binary that calls them through the PLT);
 *   - expose amd64compat_cpuid() for a caller that wants the module's
 *     leaf-1 view.
 * Getting ld.so itself past x86-64-v2 still needs the interpreter to
 * observe these bits. That is not possible from LD_PRELOAD alone on
 * current glibc. See README.
 */

typedef unsigned int u32;

static void
real_cpuid(u32 leaf, u32 sub, u32 *a, u32 *b, u32 *c, u32 *d)
{
	__asm__ __volatile__(
	    "cpuid"
	    : "=a"(*a), "=b"(*b), "=c"(*c), "=d"(*d)
	    : "0"(leaf), "2"(sub));
}

static void
spoof(u32 leaf, u32 sub, u32 *a, u32 *b, u32 *c, u32 *d)
{
	real_cpuid(leaf, sub, a, b, c, d);
	if (leaf == 1 && sub == 0) {
		*c |= (1u << 9);	/* SSSE3 */
		*c |= (1u << 19);	/* SSE4.1 */
		*c |= (1u << 20);	/* SSE4.2 */
	}
}

/* Same feature bits the module's CPUID advertise path would set. */
void
amd64compat_cpuid(u32 leaf, u32 sub, u32 *a, u32 *b, u32 *c, u32 *d)
{
	spoof(leaf, sub, a, b, c, d);
}

int
__get_cpuid_count(u32 leaf, u32 sub, u32 *a, u32 *b, u32 *c, u32 *d)
{
	spoof(leaf, sub, a, b, c, d);
	return (1);
}

int
__get_cpuid(u32 leaf, u32 *a, u32 *b, u32 *c, u32 *d)
{
	return (__get_cpuid_count(leaf, 0, a, b, c, d));
}
