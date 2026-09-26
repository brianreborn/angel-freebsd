#!/rescue/sh
# Build and install the already-patched GENERIC-DEBUG. Does not reboot.
# The source tree already has P2_AMD64COMPAT and amd64compat_ud.
# The installed /boot/kernel does not, until this finishes.
set -eu
if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /bin/sh $0" >&2
	exit 1
fi
if ! grep -q amd64compat_ud /usr/src/sys/amd64/amd64/trap.c; then
	echo "kernel source is missing amd64compat_ud" >&2
	exit 1
fi
cd /usr/src
make -j2 buildkernel KERNCONF=GENERIC-DEBUG
# This host installs the kernel from pkgbase. Without the flag,
# installkernel refuses to replace /boot/kernel. The previous kernel
# is saved as /boot/kernel.old (stock GENERIC-DEBUG, no translator).
ALLOW_PKGBASE_INSTALLKERNEL=yes make installkernel KERNCONF=GENERIC-DEBUG
echo "installed. /boot/kernel.old is the kernel that was just replaced."
echo "Reboot, then: /bin/sh /home/green/Projects/amd64compat/test-pshufb.sh"
