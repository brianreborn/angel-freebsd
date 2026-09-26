# CUDA support requirements: GeForce 8600 GT

Status: requirements only. Nothing in this note is installed by itself.

## Goal

Compile and run CUDA programs on the GeForce 8600 GT in this FreeBSD 15.1 machine.

## Hardware

| Item | Value |
|---|---|
| GPU | NVIDIA GeForce 8600 GT, 256 MB |
| PCI id | `10de:0402` (G84, revision A1) |
| Location | `pci1:0:0`, the boot display |
| Architecture | Tesla |
| Compute capability | **1.1** (`sm_11`) |
| Host | FreeBSD 15.1-RELEASE-p3 GENERIC-DEBUG, AMD Athlon II (no x86-64-v2) |

## Hard limit: the CPU

The Athlon II is baseline amd64. It does not implement x86-64-v2 (no SSSE3 as a baseline feature set, no SSE4.1, no SSE4.2). Any binary built for x86-64-v2 or newer faults at process start, before `main`. That includes the Rocky 9 userland already installed under the linuxulator.

This is the requirement that decides what we can run. Newer drivers, other toolkits, and other compat layers are all available to try. If their binaries need v2, they will not start on this CPU.

## What matches this GPU

1. **Driver.** `nvidia-driver-340` / `nvidia-kmod-340`, module `nvidia`. NVIDIA pairs this branch with CUDA 6.5. Later branches (390 and up) do not claim compute 1.1.
2. **Toolkit.** CUDA **6.5** is the last release that emits `sm_11`. Installer: `cuda_6.5.14_linux_64.run` from `developer.download.nvidia.com/compute/cuda/6_5/rel/installers/`.
3. **Compiler flags.** `nvcc -arch=sm_11 -m64`. Compute 1.x is deprecated inside 6.5, but 1.1 still compiles. CUDA 7.0 and later do not accept this chip.
4. **Runtime.** The 340 driver supplies `libcuda`. A binary built for `sm_11` is what this GPU can load.

## nvcc on this host

`nvcc` from the 6.5 runfile is a 2014 Linux executable. It is not a FreeBSD binary. It predates x86-64-v2, so the compiler itself is the right CPU target. The Rocky 9 linuxulator is not: its loader and libc are v2 and will not start it.

Ways to get a running `nvcc` on this CPU:

- an older Linux compat base that is still baseline amd64, such as `linux_base-c7`, with the extracted toolkit on `PATH`, or
- the Windows CUDA 6.5 toolkit on the existing Windows install, when that disk is booted.

Extracting the toolkit onto the FreeBSD disk does not, by itself, make `nvcc` run.

## Done when

- The NVIDIA kernel module that is loaded can see the 8600 GT.
- `nvcc --version` reports release 6.5 and the process actually starts on this CPU.
- A small `.cu` built with `-arch=sm_11` runs on this GPU and not only on the CPU.
- The 340 Xorg device (`PCI:1:0:0`, `IgnoreABI`) still starts Plasma on X11 afterward.

## Progress

2026-09-26: Confirmed `nvidia-driver-340-340.108_5` and `nvidia-kmod-340-340.108.1500068` are installed, `kld_list` includes `nvidia`, and dmesg shows `nvidia0: <GeForce 8600 GT>` on `vgapci0` at pci1:0:0. Did not load/unload the module, reboot, or edit live Xorg (`20-nvidia.conf` remains IgnoreABI + `PCI:2:0:0`). `linux_base-c7` is absent; only `linux_base-rl9-9.7`. Did not install c7 (it would replace `/compat/linux`). CUDA 6.5 runfile not on disk; this shell is Rocky bash and dies with `CPU does not support x86-64-v2`, so `nvcc` was not started. Added `/home/green/Projects/cuda-8600gt/{NOTES.md,vadd.cu,build.sh}`.
