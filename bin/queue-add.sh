#!/BSD/sh
# Publish one script, then wake the root waiter. No polling.
# Usage: queue-add.sh id-name <<'EOF'
# # title: ...
# commands
# EOF
set -eu
RQ_HOME=${RQ_HOME:-/home/${RQ_GROUP:-green}}
id=${1:?id}
pend=/var/root-queue/pending
note=$RQ_HOME/root-queue/notes/$id
tmp=$pend/$id.sh.partial
mkdir -p $RQ_HOME/root-queue/notes $RQ_HOME/root-queue/wait-log
if [ ! -p "$note" ]; then
	mkfifo -m 644 "$note"
fi
cat > "$tmp"
mv "$tmp" "$pend/$id.sh"
echo "queued $id"
