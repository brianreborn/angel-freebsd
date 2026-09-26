#!/BSD/sh
# Apply the in-kernel SSE translator, set up the local CentOS 7 tree,
# build GENERIC-DEBUG, and reboot. Stops before reboot if a step fails.
#
#   /bin/sh /home/green/Projects/roll-both.sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /bin/sh $0" >&2
	exit 1
fi
if ! /bin/freebsd-version >/dev/null 2>&1; then
	echo "this shell is not FreeBSD /bin/sh" >&2
	exit 1
fi

KERNCONF=GENERIC-DEBUG
SRC=/usr/src
MOD=/home/green/Projects/amd64compat
C7=/home/green/Projects/cuda-8600gt

echo "== local CentOS 7 (does not replace /compat/linux) =="
/bin/sh "$C7/setup-local-c7.sh"
cc -O2 -o "$C7/c7run" "$C7/c7run.c"
if ! grep -q '^security.bsd.unprivileged_chroot=' /etc/sysctl.conf 2>/dev/null; then
	echo 'security.bsd.unprivileged_chroot=1' >> /etc/sysctl.conf
fi
sysctl security.bsd.unprivileged_chroot=1

echo "== kernel: P2_AMD64COMPAT and in-tree translator =="
if ! grep -q P2_AMD64COMPAT "$SRC/sys/sys/proc.h"; then
	patch -d "$SRC" -p1 < "$MOD/patch/kernel-amd64compat.patch"
fi
install -m 644 "$MOD/kernel/amd64compat.c" "$SRC/sys/amd64/amd64/amd64compat.c"
install -m 644 "$MOD/sse.S" "$SRC/sys/amd64/amd64/amd64compat_sse.S"
grep -q P2_AMD64COMPAT "$SRC/sys/sys/proc.h"
grep -q amd64compat_ud "$SRC/sys/amd64/amd64/trap.c"
grep -q amd64compat_sse "$SRC/sys/conf/files.amd64"

echo "== build and install $KERNCONF =="
cd "$SRC"
make -j2 buildkernel KERNCONF="$KERNCONF" NO_KERNELCLEAN=yes
/BSD/sh "$MOD/install-kernel.sh"

echo "== reboot =="
echo "After boot: /bin/sh $MOD/test-pshufb.sh"
echo "Stock kernel if this one is bad: /boot/kernel.old"
sync
shutdown -r now "in-kernel amd64compat + user chroot switch"
