#!/BSD/sh
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
make -j2 buildkernel KERNCONF=GENERIC-DEBUG NO_KERNELCLEAN=yes
/BSD/sh /home/green/Projects/amd64compat/install-kernel.sh
echo "Reboot, then: /BSD/sh /home/green/Projects/amd64compat/test-pshufb.sh"
