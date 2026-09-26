#!/BSD/sh
# One pass: /BSD -> /rescue, unpack the inner CUDA archive, run pshufb.
set -eu
if [ ! -x /BSD/sh ]; then
	if [ "$(id -u)" -ne 0 ]; then
		echo "need root once: ln -s /rescue /BSD" >&2
		exit 1
	fi
	ln -s /rescue /BSD
fi
ls -ld /BSD /BSD/sh
/BSD/sh /home/green/Projects/cuda-8600gt/fetch-cuda.sh
/BSD/sh /home/green/Projects/amd64compat/test-pshufb.sh
