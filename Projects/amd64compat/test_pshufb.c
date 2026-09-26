/*
 * Userspace check for one translated opcode (PSHUFB) and for the SSE2
 * sequence the kernel runs (amd64compat_pshufb), without kldload.
 *
 * Build baseline: -mno-ssse3 -mno-sse4.1 -mno-sse4.2 -mno-avx.
 * The PSHUFB bytes live in a .byte directive; the compiler does not
 * execute them. Running do_pshufb() on this Athlon II raises SIGILL
 * until the module is loaded and the process is enabled. The SSE2
 * helper is executed here and must match the reference.
 */

#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

void amd64compat_pshufb(uint8_t dst[16], const uint8_t ctrl[16]);
void amd64compat_pmovzxbw(uint8_t dst[16], const uint8_t src[8]);

static void
ref_pshufb(uint8_t dst[16], const uint8_t ctrl[16])
{
	uint8_t src[16];
	int i;

	memcpy(src, dst, 16);
	for (i = 0; i < 16; i++) {
		if (ctrl[i] & 0x80)
			dst[i] = 0;
		else
			dst[i] = src[ctrl[i] & 0x0f];
	}
}

static void
ref_pmovzxbw(uint8_t dst[16], const uint8_t src[8])
{
	int i;

	for (i = 0; i < 8; i++) {
		dst[i * 2] = src[i];
		dst[i * 2 + 1] = 0;
	}
}

/* pshufb xmm1, xmm0  ==  66 0F 38 00 C8. SIGILL until the module runs. */
static void
do_pshufb(uint8_t dst[16], const uint8_t ctrl[16])
{
	__asm__ __volatile__(
	    "movdqu %1, %%xmm0\n\t"
	    "movdqu %0, %%xmm1\n\t"
	    ".byte 0x66, 0x0f, 0x38, 0x00, 0xc8\n\t"
	    "movdqa %%xmm1, %0\n\t"
	    : "+m"(*(uint8_t(*)[16])dst)
	    : "m"(*(const uint8_t(*)[16])ctrl)
	    : "xmm0", "xmm1", "memory");
}

static volatile sig_atomic_t saw_ill;

static void
on_ill(int sig)
{
	saw_ill = 1;
	_exit(2);
}

int
main(void)
{
	static const uint8_t table[16] = {
		0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
		0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
	};
	static const uint8_t ctrl[16] = {
		0x01, 0x00, 0x0f, 0x80, 0x10, 0x05, 0x7f, 0x08,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	};
	static const uint8_t bytes[8] = {
		0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80
	};
	uint8_t a[16] __attribute__((aligned(16)));
	uint8_t b[16] __attribute__((aligned(16)));
	uint8_t z[16] __attribute__((aligned(16)));
	uint8_t expect[16] __attribute__((aligned(16)));
	struct sigaction sa;

	memcpy(a, table, 16);
	memcpy(b, table, 16);
	amd64compat_pshufb(a, ctrl);
	ref_pshufb(b, ctrl);
	if (memcmp(a, b, 16) != 0) {
		fprintf(stderr, "pshufb SSE2 sequence != reference\n");
		return (1);
	}

	memset(z, 0x5a, 16);
	memset(expect, 0x5a, 16);
	amd64compat_pmovzxbw(z, bytes);
	ref_pmovzxbw(expect, bytes);
	if (memcmp(z, expect, 16) != 0) {
		fprintf(stderr, "pmovzxbw SSE2 sequence != reference\n");
		return (1);
	}

	printf("sse2 sequences ok\n");

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_ill;
	sigaction(SIGILL, &sa, NULL);
	memcpy(a, table, 16);
	do_pshufb(a, ctrl);
	if (memcmp(a, b, 16) != 0) {
		fprintf(stderr, "hardware/emulated pshufb != reference\n");
		return (1);
	}
	printf("pshufb opcode ok\n");
	return (0);
}
