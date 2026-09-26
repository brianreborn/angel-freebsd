#!/bin/sh
# Run a program inside the local c7 user chroot.
# Usage: /bin/sh c7exec.sh /path-inside-the-jail [args...]
# Example: /bin/sh c7exec.sh /compat/linux/bin/bash --version
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
JAIL=$ROOT/c7jail

if [ "$#" -lt 1 ]; then
	echo "usage: /bin/sh c7exec.sh /path-inside-c7jail [args...]" >&2
	exit 2
fi
if [ ! -x "$ROOT/c7run" ]; then
	cc -O2 -o "$ROOT/c7run" "$ROOT/c7run.c"
fi
exec "$ROOT/c7run" "$JAIL" "$@"
