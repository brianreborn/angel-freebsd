#!/BSD/sh
# Commit the recent script changes. Does not reboot and does not add
# the CentOS tree or the CUDA tarball.
set -eu
cd /home/green
git add \
	.gitignore \
	bin/apply-system.sh \
	bin/commit-and-reboot.sh \
	bin/commit-now.sh \
	bin/fbsd-sh \
	bin/grok-boot.sh \
	bin/grok-worker.sh \
	bin/install-grok-crontab.sh \
	bin/try-all.sh \
	Projects/amd64compat \
	Projects/roll-both.sh \
	Projects/fix-jacks.sh \
	Projects/install-jack-hints.sh
git reset -q -- Projects/cuda-8600gt/c7jail Projects/cuda-8600gt/pkg-cache || true
if git diff --cached --quiet; then
	echo "nothing to commit"
	exit 0
fi
git commit -m "$(cat <<'EOF'
Keep kernel builds incremental and start grok-worker after netwait.

buildkernel passes NO_KERNELCLEAN so cleandir does not wipe the object
tree. The @reboot session is screen -S grok-worker and waits on
rc.d/netwait before resuming grok.
EOF
)"
git status --short
git log -1 --oneline
