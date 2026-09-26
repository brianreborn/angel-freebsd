#!/bin/sh
# Persist the ALC662 jack-sense workaround in the boot hints.
set -eu
if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /bin/sh $0" >&2
	exit 1
fi
f=/boot/device.hints
if grep -q 'hint.hdaa.0.nid24.config' "$f"; then
	echo "already present in $f"
	exit 0
fi
cat >> "$f" <<'EOF'
# ALC662: ignore jack sense on the headphone pins so they cannot mute
# the rear line-out (pcm0 nid 20) or the front headphone jack (pcm2 nid 27).
hint.hdaa.0.nid24.config="misc=1"
hint.hdaa.0.nid27.config="misc=1"
EOF
echo "wrote $f"
