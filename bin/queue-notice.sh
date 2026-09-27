#!/BSD/sh
# Print one DONE or FAILED line when a root-queue result appears.
# This session is notified on each line. No fifo and no signal.
set -eu
res=/var/root-queue/results
seen=/home/green/root-queue/seen
mkdir -p /home/green/root-queue
touch "$seen"
while true; do
	for f in "$res"/*; do
		if [ ! -f "$f" ]; then
			continue
		fi
		id=$(basename "$f")
		if grep -q "^$id$" "$seen"; then
			continue
		fi
		printf '%s\n' "$id" >> "$seen"
		if grep -q '^status ran$' "$f" && grep -q '^exit 0$' "$f"; then
			echo "DONE $id"
		else
			echo "FAILED $id"
		fi
	done
	sleep 1
done
