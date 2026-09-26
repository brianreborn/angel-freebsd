#!/bin/sh
# Build vadd.cu with CUDA 6.5 for sm_11 only.
# Does not use Rocky 9 (/compat/linux while linux_base-rl9 is installed).
# Exits non-zero unless nvcc itself actually starts.

set -u

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
NVCC=${NVCC:-"$ROOT/cuda-6.5/bin/nvcc"}
SRC="$ROOT/vadd.cu"
OUT="$ROOT/vadd"

fail() {
	echo "build.sh: $*" >&2
	exit 1
}

if [ ! -f "$SRC" ]; then
	fail "missing $SRC"
fi

if [ ! -x "$NVCC" ]; then
	fail "nvcc is not runnable at $NVCC.
Extract cuda_6.5.14_linux_64.run with --extract into $ROOT (toolkit only).
Do not execute nvcc via the Rocky 9 loader in /compat/linux: that glibc
is x86-64-v2 and exits before main on this Athlon II.
linux_base-c7 is not installed; do not point NVCC at Rocky paths."
fi

# Refuse the Rocky dynamic linker even if someone copied nvcc under it.
case "$NVCC" in
/compat/linux/*)
	fail "refusing NVCC under /compat/linux ($NVCC). That tree is Rocky 9, not CentOS 7."
	;;
esac

vers=$("$NVCC" --version 2>&1) || fail "nvcc did not start ($NVCC):
$vers
This CPU has no x86-64-v2 (no SSSE3/SSE4.1/SSE4.2). A Rocky 9 loader
prints: Fatal glibc error: CPU does not support x86-64-v2.
nvcc from CUDA 6.5 must be started against linux_base-c7, not Rocky 9."

echo "$vers" | grep -q "release 6.5" || fail "nvcc started but is not CUDA 6.5:
$vers"

echo "$vers"
exec "$NVCC" -arch=sm_11 -m64 -o "$OUT" "$SRC"
