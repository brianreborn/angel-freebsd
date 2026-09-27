#!/BSD/sh
# Publish one script, then wake the root waiter. No polling.
# Usage: queue-add.sh id-name <<'EOF'
# # title: ...
# commands
# EOF
set -eu
id=${1:?id}
pend=/var/root-queue/pending
tmp=$pend/$id.sh.partial
cat > "$tmp"
mv "$tmp" "$pend/$id.sh"
mkdir -p /home/green/root-queue/pids /home/green/root-queue/wait-log
# Register for USR1 before the root waiter can finish the item.
/BSD/sh /home/green/bin/queue-wait.sh "$id" > "/home/green/root-queue/wait-log/$id" 2>&1 &
echo "queued $id waiting $!"
