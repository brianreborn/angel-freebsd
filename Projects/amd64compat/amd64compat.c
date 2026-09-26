/*-
 * amd64compat — user #UD translator for the SSSE3 / SSE4.1 / SSE4.2 gap.
 *
 * Hook point (after patch/trap-ud-hook.patch):
 *   trap() in sys/amd64/amd64/trap.c, user-mode case T_PRIVINFLT.
 *   The module sets amd64_ud_hook. Return 0 means the instruction was
 *   emulated and tf_rip already advanced. Any other return leaves the
 *   existing SIGILL / ILL_PRVOPC path unchanged.
 *
 * Kernel #UD never reaches the hook (it is inside TRAPF_USERMODE).
 * Processes not in the enable set are unchanged.
 *
 * Covered opcodes (anything else returns "not handled"):
 *   SSSE3   PSHUFB     66 0F 38 00 /r     xmm, xmm/m128
 *   SSE4.1  PMOVSXBW   66 0F 38 20 /r     xmm, xmm/m64
 *   SSE4.1  PMOVZXBW   66 0F 38 30 /r     xmm, xmm/m64
 *   SSE4.1  PMOVZXBD   66 0F 38 31 /r     xmm, xmm/m32
 *   SSE4.2  CRC32      F2 0F 38 F0 /r     r32/r64, r/m8
 *   SSE4.2  CRC32      F2 0F 38 F1 /r     r32, r/m32  or  r64, r/m64
 *
 * Forms: legacy prefixes, REX, ModRM, SIB, register or memory.
 * VEX/EVEX, LOCK, and any opcode not in the table are not handled.
 * Misaligned memory operands are not handled (hardware would have
 * raised #GP, which this #UD path cannot reconstruct precisely).
 *
 * XMM work runs in the thread's kernel FPU context (fpu_kern_enter)
 * after the user save has been written back by fpuexit. The SSE2
 * sequence reads and writes that save area. There is no return to
 * user mode to perform the substitute.
 *
 * CPUID: user-mode CPUID does not trap on this kernel (no CPUID
 * faulting MSR path, and trap.c does not intercept it). Advertising
 * SSSE3/SSE4.1/SSE4.2 for a real CPUID instruction therefore cannot
 * be done from this module. The matching bits are in cpuid_preload.c,
 * which is not on the translate path. See README.
 *
 * Enable is per process, off by default, shared by threads (one pid),
 * inherited across fork (process_fork) and exec (the pid does not
 * change). No P2_* bit is free without a kernel rebuild; the set
 * lives in the module.
 */

#include <sys/param.h>
#include <sys/module.h>
#include <sys/kernel.h>
#include <sys/systm.h>
#include <sys/proc.h>
#include <sys/lock.h>
#include <sys/mutex.h>
#include <sys/sysctl.h>
#include <sys/eventhandler.h>
#include <sys/smp.h>
#include <sys/malloc.h>

#include <machine/fpu.h>
#include <machine/md_var.h>
#include <machine/pcb.h>
#include <machine/frame.h>
#include <machine/pcpu.h>
#include <machine/atomic.h>

#include <x86/fpu.h>

void amd64compat_pshufb(uint8_t dst[16], const uint8_t ctrl[16]);
void amd64compat_pmovzxbw(uint8_t dst[16], const uint8_t src[8]);
void amd64compat_pmovsxbw(uint8_t dst[16], const uint8_t src[8]);
void amd64compat_pmovzxbd(uint8_t dst[16], const uint8_t src[4]);
int amd64compat_ud(struct trapframe *);

static struct fpu_kern_ctx **fpu_ctx;
static MALLOC_DEFINE(M_AMD64COMPAT, "amd64compat", "amd64 compat");

#ifdef AMD64COMPAT_INKERNEL

static int
compat_enabled(struct proc *p)
{
	return (p != NULL && (p->p_flag2 & P2_AMD64COMPAT) != 0);
}

static int
sysctl_compat_enable(SYSCTL_HANDLER_ARGS)
{
	struct proc *p = curproc;
	int val, error;

	if (p == NULL)
		return (ENXIO);
	val = compat_enabled(p);
	error = sysctl_handle_int(oidp, &val, 0, req);
	if (error != 0 || req->newptr == NULL)
		return (error);
	PROC_LOCK(p);
	if (val)
		p->p_flag2 |= P2_AMD64COMPAT;
	else
		p->p_flag2 &= ~P2_AMD64COMPAT;
	PROC_UNLOCK(p);
	return (0);
}

SYSCTL_PROC(_kern, OID_AUTO, amd64compat,
    CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_MPSAFE | CTLFLAG_CAPRW,
    0, 0, sysctl_compat_enable, "I",
    "Emulate missing SSSE3/SSE4.1/SSE4.2 opcodes in the calling process");

#else /* module: pid set, because this kernel has no P2_AMD64COMPAT yet */

extern int (*amd64_ud_hook)(struct trapframe *);
extern volatile int amd64_ud_hook_busy;

#define	COMPAT_MAX	1024

struct compat_pid {
	pid_t	pid;
	int	used;
};

static struct mtx compat_mtx;
static struct compat_pid compat_tab[COMPAT_MAX];
static eventhandler_tag tag_fork, tag_exit;
static volatile int unloading;

static int
compat_enabled(struct proc *p)
{
	pid_t pid;
	int i, on = 0;

	if (p == NULL)
		return (0);
	pid = p->p_pid;
	mtx_lock(&compat_mtx);
	for (i = 0; i < COMPAT_MAX; i++) {
		if (compat_tab[i].used && compat_tab[i].pid == pid) {
			on = 1;
			break;
		}
	}
	mtx_unlock(&compat_mtx);
	return (on);
}

static void
compat_set(pid_t pid, int on)
{
	int i, free_slot = -1;

	mtx_lock(&compat_mtx);
	for (i = 0; i < COMPAT_MAX; i++) {
		if (compat_tab[i].used && compat_tab[i].pid == pid) {
			if (!on)
				compat_tab[i].used = 0;
			mtx_unlock(&compat_mtx);
			return;
		}
		if (!compat_tab[i].used && free_slot < 0)
			free_slot = i;
	}
	if (on && free_slot >= 0) {
		compat_tab[free_slot].used = 1;
		compat_tab[free_slot].pid = pid;
	}
	mtx_unlock(&compat_mtx);
}

static int
sysctl_compat_enable(SYSCTL_HANDLER_ARGS)
{
	struct proc *p = curproc;
	int val, error;

	if (p == NULL)
		return (ENXIO);
	val = compat_enabled(p);
	error = sysctl_handle_int(oidp, &val, 0, req);
	if (error != 0 || req->newptr == NULL)
		return (error);
	compat_set(p->p_pid, val != 0);
	return (0);
}

SYSCTL_NODE(_compat, OID_AUTO, amd64compat, CTLFLAG_RW | CTLFLAG_MPSAFE, 0,
    "amd64 instruction compatibility");
SYSCTL_PROC(_compat_amd64compat, OID_AUTO, enable,
    CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_MPSAFE,
    0, 0, sysctl_compat_enable, "I",
    "Enable SSSE3/SSE4.1/SSE4.2 translation for the calling process");

static void
compat_on_fork(void *arg, struct proc *parent, struct proc *child, int flags)
{
	if (parent == NULL || child == NULL)
		return;
	if (compat_enabled(parent))
		compat_set(child->p_pid, 1);
}

static void
compat_on_exit(void *arg, struct proc *p)
{
	if (p != NULL)
		compat_set(p->p_pid, 0);
}

#endif /* !AMD64COMPAT_INKERNEL */

/* ---------- decoder ---------- */

#define	DEC_MAX	15

enum op_id {
	OP_NONE = 0,
	OP_PSHUFB,
	OP_PMOVSXBW,
	OP_PMOVZXBW,
	OP_PMOVZXBD,
	OP_CRC32_B,
	OP_CRC32_V,
};

struct decoded {
	enum op_id	op;
	int		len;
	uint8_t		rex;
	uint8_t		modrm;
	uint8_t		sib;
	uint8_t		has_sib;
	uint8_t		addr32;		/* 0x67 */
	uint8_t		seg;		/* 0x64 fs, 0x65 gs, else 0 */
	int32_t		disp;
	uint8_t		rip_rel;
};

static int
fetch_insn(struct trapframe *tf, uint8_t *buf, int *outlen)
{
	int n;

	for (n = DEC_MAX; n > 0; n--) {
		if (copyin_nofault((void *)(uintptr_t)tf->tf_rip, buf, n) == 0) {
			*outlen = n;
			return (0);
		}
	}
	return (EFAULT);
}

static int
dec_modrm(const uint8_t *b, int avail, int off, struct decoded *d)
{
	int mod, rm, need, sib_base;

	if (off >= avail)
		return (-1);
	d->modrm = b[off++];
	mod = d->modrm >> 6;
	rm = d->modrm & 7;
	d->has_sib = 0;
	d->rip_rel = 0;
	d->disp = 0;
	need = 0;

	if (mod != 3 && rm == 4) {
		if (off >= avail)
			return (-1);
		d->sib = b[off++];
		d->has_sib = 1;
	}

	if (mod == 3)
		return (off);
	if (mod == 1)
		need = 1;
	else if (mod == 2)
		need = 4;
	else if (!d->has_sib && rm == 5) {
		need = 4;
		d->rip_rel = !d->addr32;
	} else if (d->has_sib) {
		sib_base = d->sib & 7;
		if (mod == 0 && sib_base == 5 && (d->rex & 0x1) == 0)
			need = 4;
	}
	if (off + need > avail)
		return (-1);
	if (need == 1)
		d->disp = (int8_t)b[off];
	else if (need == 4)
		d->disp = (int32_t)((uint32_t)b[off] |
		    ((uint32_t)b[off + 1] << 8) |
		    ((uint32_t)b[off + 2] << 16) |
		    ((uint32_t)b[off + 3] << 24));
	return (off + need);
}

static int
decode(const uint8_t *b, int avail, struct decoded *d)
{
	int off = 0;
	uint8_t mand = 0;
	uint8_t op0, op1, op2;
	uint8_t rex_seen = 0;

	memset(d, 0, sizeof(*d));
	while (off < avail) {
		uint8_t p = b[off];

		if (p == 0x66 || p == 0xf2 || p == 0xf3) {
			mand = p;
			rex_seen = 0;
			off++;
			continue;
		}
		if (p == 0x67) {
			d->addr32 = 1;
			rex_seen = 0;
			off++;
			continue;
		}
		if (p == 0x64 || p == 0x65) {
			d->seg = p;
			rex_seen = 0;
			off++;
			continue;
		}
		if (p == 0xf0 || p == 0x26 || p == 0x2e || p == 0x36 ||
		    p == 0x3e) {
			/* LOCK or ignored segment/branch prefix. */
			if (p == 0xf0)
				return (1);
			rex_seen = 0;
			off++;
			continue;
		}
		if (p >= 0x40 && p <= 0x4f) {
			rex_seen = p;
			off++;
			continue;
		}
		break;
	}
	d->rex = rex_seen;
	if (off >= avail || b[off] != 0x0f)
		return (1);
	off++;
	if (off >= avail)
		return (1);
	op0 = b[off++];
	if (op0 != 0x38)
		return (1);
	if (off >= avail)
		return (1);
	op1 = b[off++];
	op2 = mand;

	if (op2 == 0x66 && op1 == 0x00)
		d->op = OP_PSHUFB;
	else if (op2 == 0x66 && op1 == 0x20)
		d->op = OP_PMOVSXBW;
	else if (op2 == 0x66 && op1 == 0x30)
		d->op = OP_PMOVZXBW;
	else if (op2 == 0x66 && op1 == 0x31)
		d->op = OP_PMOVZXBD;
	else if (op2 == 0xf2 && op1 == 0xf0)
		d->op = OP_CRC32_B;
	else if (op2 == 0xf2 && op1 == 0xf1)
		d->op = OP_CRC32_V;
	else
		return (1);

	off = dec_modrm(b, avail, off, d);
	if (off < 0)
		return (1);
	d->len = off;
	return (0);
}

static uint64_t *
gpr(struct trapframe *tf, int reg)
{
	switch (reg & 15) {
	case 0: return (&tf->tf_rax);
	case 1: return (&tf->tf_rcx);
	case 2: return (&tf->tf_rdx);
	case 3: return (&tf->tf_rbx);
	case 4: return (&tf->tf_rsp);
	case 5: return (&tf->tf_rbp);
	case 6: return (&tf->tf_rsi);
	case 7: return (&tf->tf_rdi);
	case 8: return (&tf->tf_r8);
	case 9: return (&tf->tf_r9);
	case 10: return (&tf->tf_r10);
	case 11: return (&tf->tf_r11);
	case 12: return (&tf->tf_r12);
	case 13: return (&tf->tf_r13);
	case 14: return (&tf->tf_r14);
	default: return (&tf->tf_r15);
	}
}

static int
ea_compute(struct thread *td, struct trapframe *tf, const struct decoded *d,
    uintptr_t insn_end, uintptr_t *addr)
{
	int mod = d->modrm >> 6;
	int rm = d->modrm & 7;
	uint64_t base = 0, index = 0;
	int scale, idx, breg, has_base = 1;

	if (mod == 3)
		return (EINVAL);
	if (!d->has_sib && mod == 0 && rm == 5 && !d->addr32) {
		*addr = insn_end + (int64_t)d->disp;
		goto seg;
	}
	if (!d->has_sib && mod == 0 && rm == 5 && d->addr32) {
		*addr = (uint32_t)d->disp;
		goto seg;
	}
	if (!d->has_sib) {
		breg = rm + ((d->rex & 0x1) ? 8 : 0);
		base = *gpr(tf, breg);
	} else {
		scale = d->sib >> 6;
		idx = ((d->sib >> 3) & 7) + ((d->rex & 0x2) ? 8 : 0);
		breg = (d->sib & 7) + ((d->rex & 0x1) ? 8 : 0);
		if (!((d->sib >> 3) == 4 && (d->rex & 0x2) == 0))
			index = *gpr(tf, idx) << scale;
		if (mod == 0 && (d->sib & 7) == 5 && (d->rex & 0x1) == 0)
			has_base = 0;
		if (has_base)
			base = *gpr(tf, breg);
	}
	*addr = base + index + (int64_t)d->disp;
	if (d->addr32)
		*addr = (uint32_t)*addr;
seg:
	if (d->seg == 0x64)
		*addr += (uintptr_t)td->td_pcb->pcb_fsbase;
	else if (d->seg == 0x65)
		*addr += (uintptr_t)td->td_pcb->pcb_gsbase;
	return (0);
}

static int
read_rm8(struct trapframe *tf, int reg, int has_rex, uint8_t *out)
{
	uint64_t v = *gpr(tf, reg & 15);

	if (!has_rex && reg >= 4 && reg <= 7)
		*out = (uint8_t)(v >> 8);
	else
		*out = (uint8_t)v;
	return (0);
}

static uint32_t
crc32c_byte(uint32_t crc, uint8_t data)
{
	int i;

	crc ^= data;
	for (i = 0; i < 8; i++)
		crc = (crc >> 1) ^ (0x82f63b78u & (uint32_t)-(int32_t)(crc & 1u));
	return (crc);
}

static uint32_t
crc32c_bytes(uint32_t crc, const uint8_t *p, int n)
{
	int i;

	for (i = 0; i < n; i++)
		crc = crc32c_byte(crc, p[i]);
	return (crc);
}

static int
xmm_index(const struct decoded *d, int which_reg)
{
	int r;

	if (which_reg)
		r = ((d->modrm >> 3) & 7) + ((d->rex & 0x4) ? 8 : 0);
	else
		r = (d->modrm & 7) + ((d->rex & 0x1) ? 8 : 0);
	if (r < 0 || r > 15)
		return (-1);
	return (r);
}

static uint8_t *
xmm_bytes(struct thread *td, int idx)
{
	struct savefpu *sv = get_pcb_user_save_td(td);

	return (sv->sv_xmm[idx].xmm_bytes);
}

static void
user_fpu_prepare(struct thread *td)
{
	struct pcb *pcb = td->td_pcb;

	critical_enter();
	if (PCPU_GET(fpcurthread) != td &&
	    (pcb->pcb_flags & PCB_USERFPUINITDONE) == 0) {
		fpu_save_area_reset(get_pcb_user_save_td(td));
		fpuuserinited(td);
	}
	critical_exit();
}

static int
do_xmm(struct thread *td, const struct decoded *d, uintptr_t end)
{
	int dreg, sreg, mem = 0;
	uint8_t srcbuf[16] __aligned(16);
	uint8_t *dst, *src;
	uintptr_t addr;
	int nbytes, error;
	u_int cpu;
	struct fpu_kern_ctx *ctx;

	dreg = xmm_index(d, 1);
	if (dreg < 0)
		return (1);
	switch (d->op) {
	case OP_PSHUFB:
		nbytes = 16;
		break;
	case OP_PMOVSXBW:
	case OP_PMOVZXBW:
		nbytes = 8;
		break;
	case OP_PMOVZXBD:
		nbytes = 4;
		break;
	default:
		return (1);
	}
	if ((d->modrm >> 6) != 3) {
		mem = 1;
		if (ea_compute(td, curthread->td_frame, d, end, &addr) != 0)
			return (1);
		/* PSHUFB's m128 faults on a split/unaligned operand (#GP).
		 * The narrower PMOV* forms are used unaligned by real code.
		 */
		if (nbytes == 16 && (addr & 15) != 0)
			return (1);
		if (copyin_nofault((void *)addr, srcbuf, nbytes) != 0)
			return (1);
		src = srcbuf;
	}

	cpu = PCPU_GET(cpuid);
	if (fpu_ctx == NULL || cpu >= (u_int)mp_ncpus || fpu_ctx[cpu] == NULL)
		return (1);
	ctx = fpu_ctx[cpu];

	user_fpu_prepare(td);
	critical_enter();
	fpu_kern_enter(td, ctx, FPU_KERN_NORMAL);
	dst = xmm_bytes(td, dreg);
	if (!mem) {
		sreg = xmm_index(d, 0);
		if (sreg < 0) {
			fpu_kern_leave(td, ctx);
			critical_exit();
			return (1);
		}
		src = xmm_bytes(td, sreg);
		if (d->op != OP_PSHUFB) {
			/* low nbytes of the source XMM; copy so a later
			 * punpck cannot alias dest == source unexpectedly.
			 * PSHUFB uses dest as the table and a separate ctrl.
			 */
			memcpy(srcbuf, src, nbytes);
			src = srcbuf;
		}
	}
	if (d->op == OP_PSHUFB) {
		if (!mem && src == dst) {
			memcpy(srcbuf, src, 16);
			src = srcbuf;
		}
		amd64compat_pshufb(dst, src);
	} else if (d->op == OP_PMOVZXBW)
		amd64compat_pmovzxbw(dst, src);
	else if (d->op == OP_PMOVSXBW)
		amd64compat_pmovsxbw(dst, src);
	else
		amd64compat_pmovzxbd(dst, src);
	error = fpu_kern_leave(td, ctx);
	critical_exit();
	return (error != 0);
}

static int
do_crc32(struct thread *td, struct trapframe *tf, const struct decoded *d,
    uintptr_t end)
{
	int reg = ((d->modrm >> 3) & 7) + ((d->rex & 0x4) ? 8 : 0);
	int rm = (d->modrm & 7) + ((d->rex & 0x1) ? 8 : 0);
	int rex_w = (d->rex & 0x8) != 0;
	int has_rex = d->rex != 0;
	uint64_t *destp = gpr(tf, reg);
	uint32_t crc;
	uint8_t buf[8];
	int nbytes, i;
	uintptr_t addr;

	crc = (uint32_t)*destp;
	if (d->op == OP_CRC32_B)
		nbytes = 1;
	else if (rex_w)
		nbytes = 8;
	else
		nbytes = 4;

	if ((d->modrm >> 6) == 3) {
		if (nbytes == 1) {
			if (read_rm8(tf, rm, has_rex, &buf[0]) != 0)
				return (1);
		} else {
			uint64_t v = *gpr(tf, rm);
			for (i = 0; i < nbytes; i++)
				buf[i] = (uint8_t)(v >> (8 * i));
		}
	} else {
		if (ea_compute(td, tf, d, end, &addr) != 0)
			return (1);
		if (copyin_nofault((void *)addr, buf, nbytes) != 0)
			return (1);
	}
	crc = crc32c_bytes(crc, buf, nbytes);
	/*
	 * Both the r32 form and the REX.W form leave a 32-bit CRC in the
	 * destination and clear bits 63:32 (same as a 32-bit write).
	 */
	*destp = crc;
	return (0);
}

/*
 * Return 0 if emulated. Nonzero: caller delivers SIGILL.
 */
int
amd64compat_ud(struct trapframe *tf)
{
	struct thread *td = curthread;
	uint8_t buf[DEC_MAX];
	int avail, handled;
	struct decoded dec;
	uintptr_t end;

#ifndef AMD64COMPAT_INKERNEL
	if (unloading)
		return (1);
#endif
	if (td->td_proc == NULL || !compat_enabled(td->td_proc))
		return (1);
	if (fetch_insn(tf, buf, &avail) != 0)
		return (1);
	if (decode(buf, avail, &dec) != 0 || dec.op == OP_NONE)
		return (1);
	end = (uintptr_t)tf->tf_rip + dec.len;

	switch (dec.op) {
	case OP_PSHUFB:
	case OP_PMOVSXBW:
	case OP_PMOVZXBW:
	case OP_PMOVZXBD:
		handled = do_xmm(td, &dec, end);
		break;
	case OP_CRC32_B:
	case OP_CRC32_V:
		handled = do_crc32(td, tf, &dec, end);
		break;
	default:
		return (1);
	}
	if (handled != 0)
		return (1);
	tf->tf_rip = end;
	return (0);
}

#ifdef AMD64COMPAT_INKERNEL
static void
amd64compat_sysinit(void *arg)
{
	int i;

	fpu_ctx = malloc(sizeof(*fpu_ctx) * mp_ncpus, M_AMD64COMPAT,
	    M_WAITOK | M_ZERO);
	for (i = 0; i < mp_ncpus; i++) {
		fpu_ctx[i] = fpu_kern_alloc_ctx(FPU_KERN_NORMAL);
		if (fpu_ctx[i] == NULL)
			panic("amd64compat: fpu ctx");
	}
}
SYSINIT(amd64compat, SI_SUB_CPU, SI_ORDER_ANY, amd64compat_sysinit, NULL);
#else
static int
amd64compat_modevent(module_t mod, int type, void *arg)
{
	int i;

	switch (type) {
	case MOD_LOAD:
		mtx_init(&compat_mtx, "amd64compat", NULL, MTX_DEF);
		fpu_ctx = malloc(sizeof(*fpu_ctx) * mp_ncpus, M_AMD64COMPAT,
		    M_WAITOK | M_ZERO);
		for (i = 0; i < mp_ncpus; i++) {
			fpu_ctx[i] = fpu_kern_alloc_ctx(FPU_KERN_NORMAL);
			if (fpu_ctx[i] == NULL) {
				while (--i >= 0)
					fpu_kern_free_ctx(fpu_ctx[i]);
				free(fpu_ctx, M_AMD64COMPAT);
				fpu_ctx = NULL;
				mtx_destroy(&compat_mtx);
				return (ENOMEM);
			}
		}
		tag_fork = EVENTHANDLER_REGISTER(process_fork, compat_on_fork,
		    NULL, EVENTHANDLER_PRI_ANY);
		tag_exit = EVENTHANDLER_REGISTER(process_exit, compat_on_exit,
		    NULL, EVENTHANDLER_PRI_ANY);
		amd64_ud_hook = amd64compat_ud;
		return (0);
	case MOD_UNLOAD:
		unloading = 1;
		amd64_ud_hook = NULL;
		while (atomic_load_int(&amd64_ud_hook_busy) != 0)
			pause("amd64c", 1);
		if (tag_fork != NULL)
			EVENTHANDLER_DEREGISTER(process_fork, tag_fork);
		if (tag_exit != NULL)
			EVENTHANDLER_DEREGISTER(process_exit, tag_exit);
		if (fpu_ctx != NULL) {
			for (i = 0; i < mp_ncpus; i++) {
				if (fpu_ctx[i] != NULL)
					fpu_kern_free_ctx(fpu_ctx[i]);
			}
			free(fpu_ctx, M_AMD64COMPAT);
		}
		mtx_destroy(&compat_mtx);
		return (0);
	default:
		return (EOPNOTSUPP);
	}
}

static moduledata_t amd64compat_mod = {
	"amd64compat",
	amd64compat_modevent,
	NULL
};

DECLARE_MODULE(amd64compat, amd64compat_mod, SI_SUB_EXEC, SI_ORDER_ANY);
MODULE_VERSION(amd64compat, 1);
#endif
