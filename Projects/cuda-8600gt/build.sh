#!/BSD/sh
# Build vadd.cu with CUDA 6.5 for sm_11, inside the CentOS 7 chroot.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
C7EXEC=$ROOT/c7exec.sh
SRC=/home/green/Projects/cuda-8600gt/vadd.cu
OUT=/home/green/Projects/cuda-8600gt/vadd
NVCC=/cuda-6.5/bin/nvcc

vers=$(/BSD/sh "$C7EXEC" "$NVCC" --version 2>&1) || {
	echo "build.sh: nvcc did not start" >&2
	printf '%s\n' "$vers" >&2
	exit 1
}
printf '%s\n' "$vers"
printf '%s\n' "$vers" | grep -q 'release 6\.5' || {
	echo "build.sh: nvcc is not release 6.5" >&2
	exit 1
}
/BSD/sh "$C7EXEC" "$NVCC" -arch=sm_11 -m64 -o "$OUT" "$SRC"
echo "built $OUT"
