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
if [ -f "$res" ]; then
	cat "$res"
	code=$(awk '/^exit / { print $2 }' "$res")
	exit "${code:-0}"
fi
# Read-only open blocks until the waiter writes. A newline ends the read.
read -r line < "$note"
printf '%s\n' "$line"
case "$line" in
*"exit "*)
	code=${line##*exit }
	exit "$code"
	;;
esac
exit 0
