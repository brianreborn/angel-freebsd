#!/BSD/sh
# Turn P2_AMD64COMPAT on for proc0, rebuild, install. Does not reboot.
set -eu
if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /BSD/sh $0" >&2
	exit 1
fi
SRC=/usr/src
if ! grep -q 'p->p_flag2 = P2_AMD64COMPAT' "$SRC/sys/kern/init_main.c"; then
	patch -d "$SRC" -p1 < /home/green/Projects/amd64compat/patch/default-on.patch
fi
cd "$SRC"
make -j2 buildkernel KERNCONF=GENERIC-DEBUG
/BSD/sh /home/green/Projects/amd64compat/install-kernel.sh
echo "reboot to make the translator the default for every process."
