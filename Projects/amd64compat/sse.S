/*-
 * SSE2 sequences for instructions this CPU does not have.
 * Baseline integer plus SSE2 only. No SSSE3, SSE4.1, or SSE4.2.
 *
 * Called with the kernel FPU context active (fpu_kern_enter).
 * Pointers are 16-byte aligned kernel addresses.
 *
 * amd64compat_pshufb(dst, ctrl)
 *     dst[i] = (ctrl[i] & 0x80) ? 0 : dst[ctrl[i] & 0x0f]
 * amd64compat_pmovzxbw(dst, src8)
 * amd64compat_pmovsxbw(dst, src8)
 * amd64compat_pmovzxbd(dst, src4)
 */

        .section .rodata
        .p2align 4
mask_0f:
        .byte 0x0f,0x0f,0x0f,0x0f,0x0f,0x0f,0x0f,0x0f
        .byte 0x0f,0x0f,0x0f,0x0f,0x0f,0x0f,0x0f,0x0f
mask_80:
        .byte 0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80
        .byte 0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80

        .text
        .p2align 4
        .globl amd64compat_pshufb
amd64compat_pshufb:
        movdqa  (%rdi), %xmm0           /* table, also the architectural dest */
        movdqa  (%rsi), %xmm1           /* control */
        movdqa  mask_80(%rip), %xmm4
        pand    %xmm1, %xmm4            /* isolated bit 7 */
        movdqa  mask_0f(%rip), %xmm2
        pand    %xmm2, %xmm1            /* nibble index */
        pcmpeqb mask_80(%rip), %xmm4    /* 0xff where the result byte is 0 */
        pxor    %xmm6, %xmm6            /* accumulated result */

        .macro PSHUFB_LANE lane word odd
        pextrw  $\word, %xmm0, %eax
        .if \odd
        shr     $8, %eax
        .endif
        and     $0xff, %eax
        movd    %eax, %xmm3
        punpcklbw %xmm3, %xmm3
        punpcklwd %xmm3, %xmm3
        pshufd  $0, %xmm3, %xmm3        /* broadcast table[lane] */
        mov     $\lane, %eax
        movd    %eax, %xmm5
        punpcklbw %xmm5, %xmm5
        punpcklwd %xmm5, %xmm5
        pshufd  $0, %xmm5, %xmm5        /* broadcast lane number */
        movdqa  %xmm1, %xmm7
        pcmpeqb %xmm5, %xmm7            /* index == n */
        movdqa  %xmm4, %xmm5
        pandn   %xmm7, %xmm5            /* match and bit 7 clear */
        pand    %xmm3, %xmm5
        por     %xmm5, %xmm6
        .endm

        PSHUFB_LANE 0 0 0
        PSHUFB_LANE 1 0 1
        PSHUFB_LANE 2 1 0
        PSHUFB_LANE 3 1 1
        PSHUFB_LANE 4 2 0
        PSHUFB_LANE 5 2 1
        PSHUFB_LANE 6 3 0
        PSHUFB_LANE 7 3 1
        PSHUFB_LANE 8 4 0
        PSHUFB_LANE 9 4 1
        PSHUFB_LANE 10 5 0
        PSHUFB_LANE 11 5 1
        PSHUFB_LANE 12 6 0
        PSHUFB_LANE 13 6 1
        PSHUFB_LANE 14 7 0
        PSHUFB_LANE 15 7 1

        movdqa  %xmm6, (%rdi)
        ret

        .p2align 4
        .globl amd64compat_pmovzxbw
amd64compat_pmovzxbw:
        movq    (%rsi), %xmm0
        pxor    %xmm1, %xmm1
        punpcklbw %xmm1, %xmm0
        movdqa  %xmm0, (%rdi)
        ret

        .p2align 4
        .globl amd64compat_pmovsxbw
amd64compat_pmovsxbw:
        movq    (%rsi), %xmm0
        punpcklbw %xmm0, %xmm0
        psraw   $8, %xmm0
        movdqa  %xmm0, (%rdi)
        ret

        .p2align 4
        .globl amd64compat_pmovzxbd
amd64compat_pmovzxbd:
        movd    (%rsi), %xmm0
        pxor    %xmm1, %xmm1
        punpcklbw %xmm1, %xmm0
        punpcklwd %xmm1, %xmm0
        movdqa  %xmm0, (%rdi)
        ret
