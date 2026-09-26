#!/BSD/sh
# Download CUDA 6.5 and extract it inside the local c7 tree.
# Does not run NVIDIA's installer and does not touch the FreeBSD kernel.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
JAIL=$ROOT/c7jail
RUN=$JAIL/cuda_6.5.14_linux_64.run
URL=https://developer.download.nvidia.com/compute/cuda/6_5/rel/installers/cuda_6.5.14_linux_64.run

if [ ! -x "$JAIL/compat/linux/usr/lib64/ld-linux-x86-64.so.2" ] &&
   [ ! -e "$JAIL/compat/linux/lib64/ld-linux-x86-64.so.2" ]; then
	echo "c7 tree missing. Run: /bin/sh $ROOT/setup-local-c7.sh" >&2
	exit 1
fi
if [ ! -x "$ROOT/c7run" ]; then
	cc -O2 -o "$ROOT/c7run" "$ROOT/c7run.c"
fi
# Payload is 972309551 bytes after a 447-line Makeself header.
# Any shorter local file is a partial fetch. Do not delete it.
# fetch -r without -F discards the local file when its mtime does not
# match the server, which is the usual case for an interrupted download.
# -F keeps the bytes we have and requests only the remainder.
PAYLOAD=972309551
have=0
if [ -f "$RUN" ]; then
	have=$(stat -f %z "$RUN")
fi
remote=$(fetch -s "$URL" 2>/dev/null || true)
remote=$(printf '%s' "$remote" | tr -cd '0-9')
if [ -z "$remote" ]; then
	echo "remote size unknown; will resume if a local file exists" >&2
	remote=0
fi
if [ "$remote" -gt 0 ] && [ "$have" -gt "$remote" ]; then
	echo "$RUN is $have bytes, remote is $remote. Not truncating it." >&2
	exit 1
fi
if [ "$remote" -eq 0 ] || [ "$have" -lt "$remote" ]; then
	echo "local $have bytes, remote ${remote:-unknown}. Resuming."
	fetch -F -r -o "$RUN" "$URL"
	have=$(stat -f %z "$RUN")
fi
if [ "$remote" -gt 0 ] && [ "$have" -ne "$remote" ]; then
	echo "still short: $have of $remote. Left $RUN in place." >&2
	exit 1
fi
chmod 755 "$RUN"
# Header must be present before we trust the payload length. A file
# that matches a wrong Content-Length still fails this check.
offset=$(head -n 447 "$RUN" | wc -c | tr -d '[:space:]')
expect=$((offset + PAYLOAD))
if [ "$have" -lt "$expect" ]; then
	echo "$RUN is $have bytes, need at least $expect for header+payload." >&2
	echo "Left $RUN in place." >&2
	exit 1
fi
mkdir -p "$JAIL/cuda-extract" "$JAIL/cuda-6.5"

# iflag=fullblock is not a conv option. conv=sync NUL-pads and must not be
# used on this gzip stream. fullblock makes count ignore short pipe reads.
makeself_unpack() {
	src=$1
	lines=$2
	bytes=$3
	dest=$4
	off=$(head -n "$lines" "$src" | wc -c | tr -d '[:space:]')
	full=$((bytes / 65536))
	rem=$((bytes % 65536))
	echo "payload offset $off ($src)"
	mkdir -p "$dest"
	set -o pipefail
	dd if="$src" bs="$off" skip=1 status=none \
	    | {
		dd ibs=65536 count="$full" iflag=fullblock status=none
		dd ibs=1 count="$rem" iflag=fullblock status=none
	    } \
	    | gzip -dc \
	    | tar -xf - -C "$dest"
	set +o pipefail
}

# Outer Makeself: 447 lines, then 972309551 bytes. Do not re-unpack if the
# inner toolkit .run is already there.
inner=$JAIL/cuda-extract/run_files/cuda-linux64-rel-6.5.14-18749181.run
if [ ! -f "$inner" ] && [ ! -x "$JAIL/cuda-6.5/bin/nvcc" ]; then
	rm -rf "$JAIL/cuda-extract"
	makeself_unpack "$RUN" 447 "$PAYLOAD" "$JAIL/cuda-extract"
fi
# Inner Makeself: 416 lines, filesizes=809171236. This is the toolkit.
if [ ! -x "$JAIL/cuda-6.5/bin/nvcc" ] && [ -f "$inner" ]; then
	rm -rf "$JAIL/cuda-6.5"
	mkdir -p "$JAIL/cuda-6.5"
	makeself_unpack "$inner" 416 809171236 "$JAIL/cuda-6.5"
	if [ ! -x "$JAIL/cuda-6.5/bin/nvcc" ]; then
		found=$(find "$JAIL/cuda-6.5" -type f -name nvcc | head -n 1)
		if [ -n "$found" ]; then
			echo "nvcc at $found"
		fi
	fi
fi
echo "extracted under $JAIL/cuda-extract"
if [ -x "$JAIL/cuda-6.5/bin/nvcc" ]; then
	/bin/sh "$ROOT/c7exec.sh" /cuda-6.5/bin/nvcc --version
else
	echo "nvcc not unpacked yet. Look in $JAIL/cuda-extract" >&2
	exit 1
fi
