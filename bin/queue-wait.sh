#!/BSD/sh
# Block until the root waiter writes this id's fifo. No polling.
# The result file is also written; if it is already there, return at once.
set -eu
id=${1:?id}
res=/var/root-queue/results/$id
note=/home/green/root-queue/notes/$id
mkdir -p /home/green/root-queue/notes
if [ -f "$res" ]; then
	cat "$res"
	code=$(awk '/^exit / { print $2 }' "$res")
	exit "${code:-0}"
fi
if [ ! -p "$note" ]; then
	mkfifo -m 644 "$note"
fi
# Holding the fifo open read-write lets the waiter write without blocking
# when this process is the reader.
exec 3<>"$note"
read -r line <&3
printf '%s\n' "$line"
case "$line" in
*"exit "*)
	code=${line##*exit }
	exit "$code"
	;;
esac
exit 0
