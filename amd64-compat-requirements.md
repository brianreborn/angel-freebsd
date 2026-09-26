# amd64 instruction-set compatibility module

Status: requirements. This is a FreeBSD kernel module for this machine, not a rebuild, not a userspace translator, and not a different Linux base.

## Goal

A process on this Athlon II can run an amd64 binary that uses instructions the CPU does not implement. The process keeps running. The kernel does not.

## The CPU gap

This CPU is baseline amd64 plus a few extras. It has SSE3, POPCNT, CMPXCHG16B, and LAHF/SAHF. It does not have SSSE3, SSE4.1, or SSE4.2. Those three are the whole distance from this chip to x86-64-v2.

Rocky 9 glibc does not find out by crashing. It reads CPUID and exits with `CPU does not support x86-64-v2` before `main`. A trap handler alone never runs. Spoofing CPUID alone makes the process use the missing opcodes and then die with `SIGILL`.

## What the module does

1. **Advertise.** For a process that has the module enabled, CPUID reports SSSE3, SSE4.1, and SSE4.2 in addition to what the silicon has. Other leaves stay honest. Rocky 9 glibc performs that check in its own startup, in user mode, and exits before any `#UD`. A Linux process therefore also needs an `LD_PRELOAD` that answers the same check the way the module's CPUID does. The preload only gets the dynamic linker past that test. It does not translate opcodes and it is not a reason to run the substitute sequence in user mode.
2. **Translate.** On a user `#UD` (`T_PRIVINFLT` in `sys/amd64/amd64/trap.c`) for one of those opcodes, the module rewrites it into instructions this CPU already runs: SSE, SSE2, and SSE3, plus baseline integer ops. The translated sequence produces the architectural result. Then `tf_rip` moves past the original instruction. No signal.
3. **Leave everything else alone.** An opcode the module does not know, a kernel `#UD`, or a process that did not enable the module still gets today's behavior, including `SIGILL`.

Advertise and translate are both required. CPUID without a translation turns the glibc check into `SIGILL`. A translation without the CPUID change never runs, because glibc exits first.

The translation runs in the kernel, on the trap, using the thread's FPU context. There is no user-mode helper, no return to user just to perform the substitute, and no C simulation of the XMM result when an SSE sequence can do it. Scalar cleanup is only for the bits SSE cannot express.

Scope of the first set stays the three missing groups. The translator is table-driven so another opcode is another entry, not another trap path.

## Instruction contract

First set:

- SSSE3
- SSE4.1
- SSE4.2

Each opcode covers the forms real code uses: mandatory prefixes, REX, ModRM, SIB, register or memory operand. The SSE sequence matches the Intel result for general-purpose registers, XMM, MXCSR, and EFLAGS where the instruction defines them. `rIP` advances by the full original length.

Unknown opcodes are not guessed.

## Where it sits

Loadable module on the existing user `#UD` path. Not bhyve `vie_*`. Not a userspace process.

Per process, off by default, inherited across `fork` and `exec`. Threads share the switch. The substitute sequence reads and writes that thread's user XMM and MXCSR from the kernel.

## Done when

- With the module off, CPUID and `#UD` behave as they do now.
- With the module on, CPUID shows SSSE3, SSE4.1, and SSE4.2, and a small program using each of those sets runs to completion on this Athlon II.
- A Rocky 9 dynamic linker that currently exits with `CPU does not support x86-64-v2` gets past that check via the `LD_PRELOAD` hook, then completes at least one missing opcode as an SSE sequence inside the kernel. The preload is not on the translate path.
- A `#UD` from an opcode still not implemented still delivers `SIGILL`.

## Progress

Landed under `/home/green/Projects/amd64compat/` (not loaded, kernel not patched in place):

- `patch/trap-ud-hook.patch` — `trap()` user `T_PRIVINFLT` calls `amd64_ud_hook`. A module cannot see this trap otherwise: the case is a direct SIGILL, and `sv_trap` is only used for page faults. User CPUID is not intercepted.
- `amd64compat.c`, `sse.S`, `Makefile` — per-process enable (`compat.amd64compat.enable`, off by default, fork/exec inheritance via the pid set), table-driven decoder, SSE2 substitutes for PSHUFB, PMOVSXBW, PMOVZXBW, PMOVZXBD, and integer CRC32 (r/m8 and r/m32/r/m64).
- `cpuid_preload.c` — leaf 1 ECX SSSE3 | SSE4.1 | SSE4.2. Does not translate opcodes.
- `test_pshufb.c` — reference check of the SSE2 sequences plus one real `pshufb` (`66 0F 38 00 C8`).

Still open: kernel rebuild with the hook (do not kldload before that); the shell in this session could not run `cc`/`make` (broken pipe / x86-64-v2 glibc), so the module and test were not built here; Rocky 9 ld.so checks CPUID before `LD_PRELOAD` is mapped, so the preload cannot by itself satisfy that check; remaining SSSE3/SSE4 opcodes are intentionally "not handled" (SIGILL).
