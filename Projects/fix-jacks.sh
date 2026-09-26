#!/bin/sh
# Unmute the ALC662 outputs and stop pin 24's jack sense from muting
# the rear jack (nid 20) on pcm0. Needs root. Does not reboot.
set -eu
if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /bin/sh $0" >&2
	exit 1
fi

unmute() {
	# Ignore a missing control. ogain is the codec EAPD switch.
	mixer -f "$1" vol 100 pcm 100 speaker 100 ogain 100 2>/dev/null || \
		mixer -f "$1" vol 100 pcm 100 2>/dev/null || true
}

unmute /dev/mixer0
unmute /dev/mixer1
unmute /dev/mixer2

# misc bit 0 (config bit 8) tells snd_hda to ignore presence detect.
# Pin 24 shares pcm0 with the rear jack and headphone-redirect mutes
# nid 20 when 24 looks connected.
for nid in 24 27; do
	line=$(sysctl -n dev.hdaa.0.nid${nid}_config)
	hex=$(printf '%s\n' "$line" | awk '{ print $1 }')
	new=$(printf '0x%08x' $((hex | 0x100)))
	echo "nid $nid: $line"
	echo "nid $nid -> $new"
	sysctl "dev.hdaa.0.nid${nid}_config=$new"
done

sysctl dev.hdaa.0.reconfig=1
unmute /dev/mixer0
unmute /dev/mixer1
unmute /dev/mixer2
echo "Rear jack is pcm0. If Pulse lost the device, select Rear Analog again."
