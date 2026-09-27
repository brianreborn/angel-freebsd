#!/BSD/sh
# reply-to for bge0 plus whichever of ue0 and ue1 currently have a default route.
set -eu
out=/etc/pf.tether.conf
{
	echo "set skip on lo0"
	echo "set state-policy if-bound"
	echo "pass out all keep state"
	echo "pass in on bge0 reply-to (bge0 192.168.1.1) keep state"
	netstat -rn -f inet | awk '
		$1 == "default" && ($4 == "ue0" || $4 == "ue1") {
			printf "pass in on %s reply-to (%s %s) keep state\n", $4, $4, $2
		}'
} > "$out"
kldload pf 2>/dev/null || true
pfctl -f "$out"
pfctl -e 2>/dev/null || true
pfctl -s rules
