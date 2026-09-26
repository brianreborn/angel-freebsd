# CUDA 6.5 on the GeForce 8600 GT — state as of this pass

No reboot. No `kldload` / `kldunload`. No X restart. Live Xorg config not edited.
`nvcc` was **not** run. The CUDA runfile is **not** on disk.

## What is installed (from `/var/log/messages` and boot logs)

| Package | Evidence |
|---|---|
| `nvidia-kmod-340-340.108.1500068` | pkg log 2026-09-26 03:26:06 |
| `nvidia-driver-340-340.108_5` | pkg log 2026-09-26 03:26:25 |
| `linux_base-rl9-9.7` | pkg log 2026-09-25 23:56:06. `/compat/linux/etc/redhat-release` is Rocky Linux 9.7 |
| `linux_base-c7` | **not installed** (no pkg log line) |

`/etc/rc.conf` has `kld_list="fusefs nvidia"` and `linux_enable="YES"`.
`/boot/modules/nvidia.ko` is present.

Kernel already attached the module to this card (do not load it again):

```
FreeBSD 15.1-RELEASE-p3 GENERIC-DEBUG amd64
vgapci0: <VGA-compatible display> ... at device 0.0 on pci1
vgapci0: Boot video device
nvidia0: <GeForce 8600 GT> on vgapci0
```

That is `pci1:0:0`, boot display. CPU line from the same dmesg:

```
CPU: AMD Athlon(tm) II X2 B24 Processor (2992.61-MHz K8-class CPU)
Features2=0x802009<SSE3,MON,CX16,POPCNT>
AMD Features2=0x37ff<LAHF,CMP,SVM,ExtAPIC,CR8,ABM,SSE4A,MAS,Prefetch,OSVW,IBS,SKINIT,WDT>
```

No SSSE3, no SSE4.1, no SSE4.2. SSE4A is not SSE4.1. This is not x86-64-v2.
Any glibc that demands v2 prints `Fatal glibc error: CPU does not support x86-64-v2` and exits before `main`.

## Xorg (left untouched)

Live file `/usr/local/etc/X11/xorg.conf.d/20-nvidia.conf`:

- `IgnoreABI` true
- Driver `nvidia`
- BusID **`PCI:2:0:0`** (what `setup-xorg.sh` wrote)

dmesg places the card at **pci1:0:0**. The running Plasma/X11 session is using the installed snippet. It was not replaced. A BusID edit would be a display change; do not do it from this session.

## What binary would be executed

Not Rocky. Not anything under `/compat/linux` while that tree is Rocky 9.
Rocky `ld-linux` / libc are v2. This agent's own `/bin/sh` is that bash: `echo hi` dies with the glibc v2 message (exit 127). So this pass could not run `pkg`, `fetch`, or `nvcc`.

Target binary, after a user-writable extract:

`/home/green/Projects/cuda-8600gt/cuda-6.5/bin/nvcc`

CUDA 6.5 `nvcc` is a 2014 Linux ELF (baseline amd64, not v2). It only starts if the linuxulator loader and libc are baseline too (`linux_base-c7`). Flags: `nvcc -arch=sm_11 -m64`.

`build.sh` in this directory calls that `nvcc` only after `nvcc --version` actually runs and the text contains `release 6.5`. Otherwise it prints why and exits non-zero. It refuses a path under `/compat/linux`.

Sample source: `vadd.cu` (host `printf` only, float kernel, 1 block × 256 threads).

## Not done, and why

- **Do not `pkg install linux_base-c7` from here.** `linux_base-c7` and `linux_base-rl9` both own `/compat/linux`. Installing c7 would remove Rocky 9. That may be what we want for `nvcc`, but it is a compat-tree replacement, so it was not executed.
- **Do not run the NVIDIA `.run` against the FreeBSD kernel.** Runfile not downloaded: `https://developer.download.nvidia.com/compute/cuda/6_5/rel/installers/cuda_6.5.14_linux_64.run` (URL responds; binary body could not be saved without `fetch`). Not in `~/Downloads`.

## Exact commands not yet run

Driver is already loaded and `nvidia0` is the 8600 GT. Do **not** run `kldload nvidia` or reboot for the module.

Do not `pkg install linux_base-c7`. That package owns `/compat/linux` and would remove Rocky 9.

A second copy lives only under `c7jail/compat/linux`. `setup-local-c7.sh` fetches the official package and extracts it there. It does not register the package and does not change `compat.linux.emul_path`.

No jail, no DTrace, no kernel change. This system already has user chroot (`security.bsd.unprivileged_chroot`, off by default). The process must also set `PROC_NO_NEW_PRIVS`. `c7run` does that and chroots into `c7jail`. The linuxulator then resolves `/compat/linux` inside that root, so the loader is CentOS 7 glibc 2.17, not Rocky. `LD_*` cannot do this: Rocky's `ld-linux` is the interpreter the kernel maps first, and it exits on the x86-64-v2 check before it reads `LD_LIBRARY_PATH`.

One host switch, once:

```sh
sysctl security.bsd.unprivileged_chroot=1
```

Then:

```sh
/bin/sh setup-local-c7.sh
/bin/sh c7exec.sh /compat/linux/bin/bash --version
```

The system `/compat/linux` stays Rocky. Extract the CUDA 6.5 toolkit under `c7jail/` (for example `c7jail/cuda-6.5`) and invoke it the same way: `/bin/sh c7exec.sh /cuda-6.5/bin/nvcc --version`.

2. Download and extract the toolkit only (no driver install):

```sh
fetch -o /home/green/Projects/cuda-8600gt/cuda_6.5.14_linux_64.run \
  https://developer.download.nvidia.com/compute/cuda/6_5/rel/installers/cuda_6.5.14_linux_64.run
chmod +x /home/green/Projects/cuda-8600gt/cuda_6.5.14_linux_64.run
/home/green/Projects/cuda-8600gt/cuda_6.5.14_linux_64.run \
  --extract=/home/green/Projects/cuda-8600gt/extract
```

Then extract the inner toolkit archive into `/home/green/Projects/cuda-8600gt/cuda-6.5` (`--help` / `--tar` on the inner `cuda-linux64-rel-6.5*.run`). Do not run the default installer.

3. After c7 is the compat base and `cuda-6.5/bin/nvcc` exists:

```sh
/home/green/Projects/cuda-8600gt/cuda-6.5/bin/nvcc --version
sh /home/green/Projects/cuda-8600gt/build.sh
/home/green/Projects/cuda-8600gt/vadd
```

`vadd` needs the already-loaded 340 `libcuda` (`LD_LIBRARY_PATH`/`/usr/local/lib` as the 340 package installed it). That run uses the GPU. It does not reload the module. It still should be done from a normal FreeBSD shell, not from Rocky.
