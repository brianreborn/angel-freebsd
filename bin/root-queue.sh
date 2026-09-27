#!/BSD/sh
# Pick up scripts the grok worker drops in the pending directory.
# Nothing in pending is read or executed in place. The file is copied
# into a root-only directory, the copy is checked against a second stat,
# then the pending name is removed. View and run use only that copy.
#
#   /BSD/sh ~/bin/root-queue.sh
#       Wait. list | next | run [id] | view id | cancel id | quit
#
# Pending (worker-writable): /var/root-queue/pending/
# Private (root, mode 0700): /var/root-queue/private/
# The worker cancels by removing its own file from pending before claim.
set -eu
export PATH=/BSD:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

Q=/var/root-queue
PEND=$Q/pending
PRIV=$Q/private
DONE=$Q/done
CANC=$Q/cancelled

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /BSD/sh $0" >&2
	exit 1
fi

install -d -o root -g green -m 1770 "$PEND"
install -d -o root -g wheel -m 700 "$PRIV" "$DONE" "$CANC"
install -d -o root -g green -m 755 "$Q/results"
install -d -o root -g green -m 1770 "$Q/waiters"
echo $$ > "$Q/waiter.pid"
trap 'rm -f "$Q/waiter.pid"' EXIT

title_of() {
	# Caller must pass a root-owned private copy.
	t=$(head -n 1 "$1" | sed -n 's/^# title: //p')
	if [ -z "$t" ]; then
		t=$(basename "$1")
	fi
	printf '%s' "$t"
}

list_pending() {
	found=0
	for f in "$PEND"/*.sh "$PRIV"/*.sh; do
		if [ ! -f "$f" ]; then
			continue
		fi
		found=1
		id=$(basename "$f" .sh)
		case "$f" in
		"$PRIV"/*) echo "$id  claimed" ;;
		*) echo "$id  pending" ;;
		esac
	done
	if [ "$found" -eq 0 ]; then
		echo "queue empty"
	fi
}

# Copy one pending script into the private directory. Retry if the
# worker changes it during the copy. Then chown it to root.
claim() {
	id=$1
	src=$PEND/$id.sh
	dst=$PRIV/$id.sh
	if [ -f "$dst" ]; then
		echo "$dst"
		return 0
	fi
	if [ ! -f "$src" ]; then
		echo "not pending: $id" >&2
		return 1
	fi
	n=0
	while [ "$n" -lt 5 ]; do
		if [ ! -f "$src" ]; then
			echo "gone: $id" >&2
			return 1
		fi
		before=$(stat -f '%d %i %z %m' "$src")
		cp -f "$src" "$dst.copy"
		after=$(stat -f '%d %i %z %m' "$src" 2>/dev/null || echo missing)
		if [ "$before" = "$after" ]; then
			mv "$dst.copy" "$dst"
			chown root:wheel "$dst"
			chmod 700 "$dst"
			rm -f "$src"
			echo "$dst"
			return 0
		fi
		n=$((n + 1))
	done
	rm -f "$dst.copy"
	echo "changed during claim: $id" >&2
	return 1
}

record() {
	id=$1
	status=$2
	code=$3
	printf 'status %s\nexit %s\n' "$status" "$code" > "$Q/results/$id"
	chmod 644 "$Q/results/$id"
	note=/home/green/root-queue/notes/$id
	if [ -p "$note" ] && [ -x /home/green/bin/queue-poke ]; then
		/home/green/bin/queue-poke "$note" "$(printf 'status %s exit %s\n' "$status" "$code")" || true
	fi
}

run_one() {
	f=$1
	id=$(basename "$f" .sh)
	echo "== run $id $(title_of "$f") =="
	set +e
	/BSD/sh "$f"
	code=$?
	set -e
	if [ "$code" -ne 0 ]; then
		echo "failed: $id ($code)" >&2
		record "$id" failed "$code"
		mv "$f" "$DONE/$id.sh"
		return 1
	fi
	mv "$f" "$DONE/$id.sh"
	record "$id" ran 0
	echo "done: $id"
}

# One key, no Enter. Escape bytes are ignored, so ^[a^[ still counts as a.
key() {
	old=$(stty -g)
	stty -echo -icanon min 0 time 5 < /dev/tty
	while true; do
		c=$(dd if=/dev/tty bs=1 count=1 2>/dev/null || true)
		case "$c" in
		a|A|d|D|v|V|s|S|q|Q|r|R|c|C)
			stty "$old" < /dev/tty
			printf '%s' "$c"
			return 0
			;;
		esac
	done
}

prompt_one() {
	f=$1
	id=$(basename "$f" .sh)
	if [ ! -f "$f" ]; then
		return 0
	fi
	echo
	echo "$id  $(title_of "$f")"
	while true; do
		printf 'a approve, d disapprove, v view, s skip, q quit '
		ans=$(key)
		echo "$ans"
		case "$ans" in
		a|A|r|R)
			run_one "$f" || true
			return 0
			;;
		v|V)
			echo "----- $id -----"
			cat "$f"
			echo "-----"
			printf 'a approve, d disapprove '
			ans2=$(key)
			echo "$ans2"
			case "$ans2" in
			a|A|r|R) run_one "$f" || true ;;
			d|D|c|C)
				if [ -f "$f" ]; then
					mv "$f" "$CANC/$id.sh"
				fi
				record "$id" cancelled 0
				echo "cancelled: $id"
				;;
			esac
			return 0
			;;
		d|D|c|C)
			if [ -f "$f" ]; then
				mv "$f" "$CANC/$id.sh"
			fi
			record "$id" cancelled 0
			echo "cancelled: $id"
			return 0
			;;
		s|S|"")
			return 0
			;;
		q|Q)
			exit 0
			;;
		*)
			echo "r, v, c, s, or q"
			;;
		esac
	done
}

do_cmd() {
	cmd=$1
	id=${2:-}
	case "$cmd" in
	list|l)
		list_pending
		;;
	run|r)
		if [ "$id" != "" ]; then
			f=$(claim "$id") || return 1
			run_one "$f"
		else
			for f in "$PEND"/*.sh "$PRIV"/*.sh; do
				if [ ! -f "$f" ]; then
					continue
				fi
				cid=$(basename "$f" .sh)
				got=$(claim "$cid") || continue
				run_one "$got" || return 1
			done
		fi
		;;
	view|v)
		f=$(claim "$id") || return 1
		echo "$id  $(title_of "$f")"
		cat "$f"
		;;
	cancel|c)
		if [ -f "$PRIV/$id.sh" ]; then
			mv "$PRIV/$id.sh" "$CANC/$id.sh"
			record "$id" cancelled 0
			echo "cancelled: $id"
			return 0
		fi
		if [ -f "$PEND/$id.sh" ]; then
			f=$(claim "$id") || return 1
			mv "$f" "$CANC/$id.sh"
			record "$id" cancelled 0
			echo "cancelled: $id"
			return 0
		fi
		echo "not pending: $id" >&2
		return 1
		;;
	next|n)
		for f in "$PEND"/*.sh "$PRIV"/*.sh; do
			if [ ! -f "$f" ]; then
				continue
			fi
			cid=$(basename "$f" .sh)
			got=$(claim "$cid") || return 1
			prompt_one "$got"
			return 0
		done
		echo "queue empty"
		;;
	help|h|"")
		echo "list | next | run [id] | view id | cancel id | quit"
		;;
	quit|q)
		exit 0
		;;
	*)
		echo "unknown: $cmd"
		;;
	esac
}

if [ "${1:-}" != "" ]; then
	do_cmd "$1" "${2:-}"
	exit 0
fi

echo "root queue. pid $$"
echo "waiting. one key, no enter: a d v s q"
list_pending
while true; do
	found=0
	for f in "$PEND"/*.sh "$PRIV"/*.sh; do
		if [ ! -f "$f" ]; then
			continue
		fi
		found=1
		cid=$(basename "$f" .sh)
		got=$(claim "$cid") || continue
		prompt_one "$got"
	done
	if [ "$found" -eq 0 ]; then
		sleep 1
	fi
done
