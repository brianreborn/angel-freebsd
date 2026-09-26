#!/BSD/sh
# Mount the Handbook linux filesystems inside the c7 chroot, commit, reboot.
# Host /compat/linux is already mounted by the linux service. A chroot does
# not see those mounts, so the same five are mounted under c7jail.
set -eu
if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /BSD/sh $0" >&2
	exit 1
fi

JAIL=/home/green/Projects/cuda-8600gt/c7jail
BASE=$JAIL/compat/linux
FSTAB=/etc/fstab

mkdir -p "$BASE/dev/shm" "$BASE/dev/fd" "$BASE/proc" "$BASE/sys" \
	"$JAIL/tmp" "$JAIL/home"

mounted() {
	mount | awk -v m="$1" '$3 == m { found = 1 } END { exit !found }'
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

# Handbook ch. 12. Order matters: dev before shm and fd.
mount_once "$BASE/dev" -t devfs devfs "$BASE/dev"
mount_once "$BASE/dev/shm" -t tmpfs -o size=1g,mode=1777 tmpfs "$BASE/dev/shm"
mount_once "$BASE/dev/fd" -t fdescfs -o linrdlnk fdescfs "$BASE/dev/fd"
mount_once "$BASE/proc" -t linprocfs linprocfs "$BASE/proc"
mount_once "$BASE/sys" -t linsysfs linsysfs "$BASE/sys"
# Handbook: share host /tmp and /home into the compat tree via nullfs.
mount_once "$JAIL/tmp" -t nullfs /tmp "$JAIL/tmp"
mount_once "$JAIL/home" -t nullfs /home "$JAIL/home"

ensure_fstab() {
	line=$1
	if grep -q "$2" "$FSTAB"; then
		return 0
	fi
	printf '%s\n' "$line" >> "$FSTAB"
	echo "fstab: $line"
}

if ! grep -q 'c7jail compat mounts' "$FSTAB"; then
	printf '\n# c7jail compat mounts (Handbook ch. 12; rc mounts do not cover a chroot)\n' >> "$FSTAB"
fi
ensure_fstab "devfs	$BASE/dev	devfs	rw,late	0	0" "$BASE/dev"
ensure_fstab "tmpfs	$BASE/dev/shm	tmpfs	rw,late,size=1g,mode=1777	0	0" "$BASE/dev/shm"
ensure_fstab "fdescfs	$BASE/dev/fd	fdescfs	rw,late,linrdlnk	0	0" "$BASE/dev/fd"
ensure_fstab "linprocfs	$BASE/proc	linprocfs	rw,late	0	0" "$BASE/proc"
ensure_fstab "linsysfs	$BASE/sys	linsysfs	rw,late	0	0" "$BASE/sys"
ensure_fstab "/tmp	$JAIL/tmp	nullfs	rw,late	0	0" "$JAIL/tmp	nullfs"
ensure_fstab "/home	$JAIL/home	nullfs	rw,late	0	0" "$JAIL/home	nullfs"

# Root does not have green's GitHub login. Copy the gh config, then
# point git at it. Do not print the token.
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
	bin/fbsd-sh \
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
if ! git diff --cached --quiet; then
	git commit -m "$(cat <<'EOF'
Save Athlon II FreeBSD work before booting the translator kernel.

amd64compat translates a few SSSE3/SSE4 opcodes on #UD. CUDA 6.5 nvcc
runs from a private CentOS 7 tree. The c7 chroot gets the Handbook
linux mounts, which the linux service does not provide inside a chroot.
EOF
)"
else
	echo "nothing new to commit"
fi
if ! git remote get-url origin >/dev/null 2>&1; then
	gh repo create brianreborn/angel-freebsd --private --source=. --remote=origin --push
else
	git push -u origin HEAD
fi
sync
shutdown -r now "boot amd64compat kernel"
