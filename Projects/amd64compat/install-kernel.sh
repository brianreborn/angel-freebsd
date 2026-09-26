#!/BSD/sh
# Install GENERIC-DEBUG without burying the stock kernel.
# installkernel moves /boot/kernel onto /boot/kernel.old and deletes the
# previous kernel.old. reinstallkernel overwrites /boot/kernel in place.
# When kernel.old has no translator, it is the stock backup: keep it.
set -eu
if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /BSD/sh $0" >&2
	exit 1
fi
cd /usr/src
target=installkernel
if [ -f /boot/kernel.old/kernel ] &&
   ! grep -a -q amd64compat_ud /boot/kernel.old/kernel; then
	echo "kernel.old is stock (no amd64compat_ud); using reinstallkernel"
	target=reinstallkernel
else
	echo "kernel.old is absent or already a translator kernel; using installkernel"
fi
ALLOW_PKGBASE_INSTALLKERNEL=yes make "$target" KERNCONF=GENERIC-DEBUG
echo "done ($target). Stock rollback stays /boot/kernel.old while it has no amd64compat_ud."
