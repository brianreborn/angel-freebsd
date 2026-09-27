#!/BSD/sh
# One root pass: system config, git push, kernel rebuild, reinstall.
# Does not reboot. Does not replace /boot/kernel.old when that kernel
# has no amd64compat_ud (the stock backup).
set -eu
if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /BSD/sh $0" >&2
	exit 1
fi

SRC=/usr/src
MOD=/home/green/Projects/amd64compat
JAIL=/home/green/Projects/cuda-8600gt/c7jail
BASE=$JAIL/compat/linux
FSTAB=/etc/fstab

echo "== translator on for proc0 =="
# A previous patch fuzz wrote the next diff header into proc.h.
if grep -F -q '++ b/sys/kern/init_main.c' "$SRC/sys/sys/proc.h"; then
	awk '
		$0 == "++ b/sys/kern/init_main.c" { skip = 1; next }
		skip && /list \*\// { skip = 0; next }
		{ print }
	' "$SRC/sys/sys/proc.h" > "$SRC/sys/sys/proc.h.new"
	mv "$SRC/sys/sys/proc.h.new" "$SRC/sys/sys/proc.h"
	rm -f "$SRC/sys/sys/proc.h.rej" "$SRC/sys/sys/proc.h.orig"
	echo "repaired proc.h"
fi
if ! grep -q 'P_TREE_FIRST_ORPHAN' "$SRC/sys/sys/proc.h"; then
	awk '
		/P_TREE_ORPHANED/ && !done {
			print
			print "#define	P_TREE_FIRST_ORPHAN	0x00000002	/* First element of orphan list */"
			done = 1
			next
		}
		{ print }
	' "$SRC/sys/sys/proc.h" > "$SRC/sys/sys/proc.h.new"
	mv "$SRC/sys/sys/proc.h.new" "$SRC/sys/sys/proc.h"
	echo "restored P_TREE_FIRST_ORPHAN"
fi
if ! grep -q 'p->p_flag2 = P2_AMD64COMPAT' "$SRC/sys/kern/init_main.c"; then
	awk '
		/p->p_flag = P_SYSTEM \| P_INMEM \| P_KPROC/ { print; next }
		/p->p_flag2 = 0;/ && !done {
			print "	/* User #UD translation is on unless a process clears it. */"
			print "	p->p_flag2 = P2_AMD64COMPAT;"
			done = 1
			next
		}
		{ print }
	' "$SRC/sys/kern/init_main.c" > "$SRC/sys/kern/init_main.c.new"
	mv "$SRC/sys/kern/init_main.c.new" "$SRC/sys/kern/init_main.c"
	echo "set P2_AMD64COMPAT on proc0"
fi

echo "== c7 chroot mounts =="
mkdir -p "$BASE/dev/shm" "$BASE/dev/fd" "$BASE/proc" "$BASE/sys" \
	"$JAIL/tmp" "$JAIL/home"

mounted() {
	mount | awk -v m="$1" '$3 == m { found = 1 } END { exit found ? 0 : 1 }'
}

mount_once() {
	point=$1
	shift
	if mounted "$point"; then
		echo "already mounted: $point"
		return 0
	fi
	mount "$@"
	echo "mounted: $point"
}

mount_once "$BASE/dev" -t devfs devfs "$BASE/dev"
mount_once "$BASE/dev/shm" -t tmpfs -o size=1g,mode=1777 tmpfs "$BASE/dev/shm"
mount_once "$BASE/dev/fd" -t fdescfs -o linrdlnk fdescfs "$BASE/dev/fd"
mount_once "$BASE/proc" -t linprocfs linprocfs "$BASE/proc"
mount_once "$BASE/sys" -t linsysfs linsysfs "$BASE/sys"
mount_once "$JAIL/tmp" -t nullfs /tmp "$JAIL/tmp"
mount_once "$JAIL/home" -t nullfs /home "$JAIL/home"

ensure_fstab() {
	line=$1
	key=$2
	if grep -q "$key" "$FSTAB"; then
		return 0
	fi
	printf '%s\n' "$line" >> "$FSTAB"
	echo "fstab: $line"
}

if ! grep -q 'c7jail compat mounts' "$FSTAB"; then
	printf '\n# c7jail compat mounts (Handbook ch. 12; rc mounts do not cover a chroot)\n' >> "$FSTAB"
fi
ensure_fstab "devfs	$BASE/dev	devfs	rw,late	0	0" "$BASE/dev	devfs"
ensure_fstab "tmpfs	$BASE/dev/shm	tmpfs	rw,late,size=1g,mode=1777	0	0" "$BASE/dev/shm"
ensure_fstab "fdescfs	$BASE/dev/fd	fdescfs	rw,late,linrdlnk	0	0" "$BASE/dev/fd"
ensure_fstab "linprocfs	$BASE/proc	linprocfs	rw,late	0	0" "$BASE/proc	linprocfs"
ensure_fstab "linsysfs	$BASE/sys	linsysfs	rw,late	0	0" "$BASE/sys	linsysfs"
ensure_fstab "/tmp	$JAIL/tmp	nullfs	rw,late	0	0" "$JAIL/tmp	nullfs"
ensure_fstab "/home	$JAIL/home	nullfs	rw,late	0	0" "$JAIL/home	nullfs"

echo "== netwait and grok-worker crontab =="
/BSD/sh /home/green/bin/install-grok-crontab.sh

echo "== git =="
mkdir -p /root/.config
rm -rf /root/.config/gh
cp -R /home/green/.config/gh /root/.config/gh
chown -R root:wheel /root/.config/gh
gh auth setup-git
cd /home/green
if [ ! -d .git ]; then
	git init
fi
git add \
	.gitignore \
	amd64-compat-requirements.md \
	cuda-8600gt-requirements.md \
	bin/apply-system.sh \
	bin/fbsd-sh \
	bin/grok-boot.sh \
	bin/grok-worker.sh \
	bin/install-grok-crontab.sh \
	bin/try-all.sh \
	bin/commit-and-reboot.sh \
	Projects/amd64compat \
	Projects/cuda-8600gt/NOTES.md \
	Projects/cuda-8600gt/build.sh \
	Projects/cuda-8600gt/c7exec.sh \
	Projects/cuda-8600gt/c7run.c \
	Projects/cuda-8600gt/fetch-cuda.sh \
	Projects/cuda-8600gt/setup-local-c7.sh \
	Projects/cuda-8600gt/vadd.cu \
	Projects/cuda-8600gt/vector_add.cu \
	Projects/fix-jacks.sh \
	Projects/install-jack-hints.sh \
	Projects/roll-both.sh
git reset -q -- Projects/cuda-8600gt/c7jail Projects/cuda-8600gt/pkg-cache || true
if git diff --cached --quiet; then
	echo "nothing new to commit"
else
	git commit -m "Apply translator default, grok-worker crontab, and c7 mounts."
fi
if ! git remote get-url origin >/dev/null 2>&1; then
	gh repo create brianreborn/angel-freebsd --private --source=. --remote=origin --push
else
	git push -u origin HEAD
fi

echo "== kernel =="
cd "$SRC"
# NO_KERNELCLEAN skips cleandir. NO_KERNELCONFIG skips re-running config,
# which rewrites the kernel Makefile and makes the tree look out of date.
make -j2 buildkernel KERNCONF=GENERIC-DEBUG \
	NO_KERNELCLEAN=yes NO_KERNELCONFIG=yes
/BSD/sh "$MOD/install-kernel.sh"
echo "done. reboot when you want proc0 to start with the translator on."
