#!/BSD/sh
# Publish one script, then wake the root waiter. No polling.
# Usage: queue-add.sh id-name <<'EOF'
# # title: ...
# commands
# EOF
set -eu
id=${1:?id}
pend=/var/root-queue/pending
note=/home/green/root-queue/notes/$id
tmp=$pend/$id.sh.partial
mkdir -p /home/green/root-queue/notes /home/green/root-queue/wait-log
if [ ! -p "$note" ]; then
	mkfifo -m 644 "$note"
fi
cat > "$tmp"
mv "$tmp" "$pend/$id.sh"
echo "queued $id"
