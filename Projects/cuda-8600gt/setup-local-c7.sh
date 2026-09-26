#!/BSD/sh
# Install CentOS 7 (linux_base-c7) under this project only.
# Does not pkg-install it, does not write /compat/linux, does not touch Rocky 9.
#
# Run with the FreeBSD shell, not the Rocky bash:
#   /bin/sh setup-local-c7.sh
#
# Fetch and extract work as a normal user. Entering the tree needs root
# because chroot(2) is what points the linuxulator at this copy. The global
# sysctl compat.linux.emul_path stays /compat/linux.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
JAIL=$ROOT/c7jail
CACHE=$ROOT/pkg-cache

if ! /bin/freebsd-version >/dev/null 2>&1; then
	echo "setup-local-c7.sh: run this with FreeBSD /bin/sh, not Rocky bash." >&2
	exit 1
fi

mkdir -p "$CACHE" "$JAIL"

echo "Fetching linux_base-c7 into $CACHE (no install)..."
pkg fetch -y -o "$CACHE" linux_base-c7

pkgfile=$(find "$CACHE" -name 'linux_base-c7-*.pkg' -type f | head -n 1)
if [ -z "$pkgfile" ]; then
	echo "setup-local-c7.sh: pkg fetch did not leave a linux_base-c7-*.pkg under $CACHE" >&2
	exit 1
fi

# pkg stores names as /compat/linux/... . That leading slash is normal.
# Reject anything that is not that tree or a pkg metadata member (+MANIFEST).
# Extract with the slash stripped so -C writes c7jail/compat/linux, not
# the system /compat/linux.
tar -tf "$pkgfile" | awk '
	BEGIN { bad = 0 }
	{
		p = $0
		sub(/^\.\//, "", p)
		sub(/^\//, "", p)
		if (p ~ /(^|\/)\.\.(\/|$)/) {
			print "unsafe path: " $0 > "/dev/stderr"
			bad = 1
		} else if (p !~ /^(\+|$)/ && p !~ /^compat\/linux(\/|$)/) {
			print "unexpected path: " $0 > "/dev/stderr"
			bad = 1
		}
	}
	END { exit bad }
'

echo "Extracting $pkgfile into $JAIL"
tar -xf "$pkgfile" -C "$JAIL" -s '|^\./||' -s '|^/||' --exclude '+*'

if [ ! -e "$JAIL/compat/linux/lib64/ld-linux-x86-64.so.2" ] &&
   [ ! -e "$JAIL/compat/linux/usr/lib64/ld-linux-x86-64.so.2" ]; then
	echo "setup-local-c7.sh: extracted tree has no amd64 ld-linux." >&2
	exit 1
fi

# FreeBSD shell inside the chroot, so we can launch a Linux binary from there.
mkdir -p "$JAIL/rescue" "$JAIL/bin" "$JAIL/dev" "$JAIL/tmp" "$JAIL/work"
if [ ! -x "$JAIL/rescue/sh" ]; then
	cp /rescue/sh "$JAIL/rescue/sh"
	chmod 555 "$JAIL/rescue/sh"
fi
ln -sfn /rescue/sh "$JAIL/bin/sh"

# Host /compat/linux must still be Rocky after this.
if [ -r /compat/linux/etc/redhat-release ]; then
	echo "System /compat/linux is still: $(cat /compat/linux/etc/redhat-release)"
fi
echo "Local CentOS 7 tree: $JAIL/compat/linux"
echo "Once: sysctl security.bsd.unprivileged_chroot=1"
echo "Then: /bin/sh $ROOT/c7exec.sh /compat/linux/bin/bash --version"
