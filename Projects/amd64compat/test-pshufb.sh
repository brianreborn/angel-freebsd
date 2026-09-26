#!/rescue/sh
# Build and run the PSHUFB check in this process tree.
# kern.amd64compat is per process and is inherited across fork, so the
# shell that sets it must be the parent of the test.
set -eu
cd "$(dirname "$0")"

if ! sysctl kern.amd64compat >/dev/null 2>&1; then
	echo "kern.amd64compat is missing. The running kernel has no translator." >&2
	echo "Stock kernel is /boot/kernel.old. The new kernel is /boot/kernel." >&2
	exit 1
fi
sysctl kern.amd64compat=1

cc -O2 -mno-ssse3 -mno-sse4.1 -mno-sse4.2 -mno-avx \
	-o test_pshufb test_pshufb.c sse.S
./test_pshufb
