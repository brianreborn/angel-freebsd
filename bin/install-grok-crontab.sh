#!/BSD/sh
# Install green's @reboot screen session. Keeps unrelated crontab lines.
# Replaces an older "screen -dmS grok" line, including grok-worker.
set -eu
TAB=$(mktemp /tmp/crontab.XXXXXX)
trap 'rm -f "$TAB" "${TAB}.new"' EXIT
if ! crontab -u green -l > "$TAB" 2>/dev/null; then
	: > "$TAB"
fi
# grep -v exits 1 when every line is removed. That must not abort under set -e.
if ! grep -v 'screen -dmS grok' "$TAB" > "${TAB}.new"; then
	: > "${TAB}.new"
fi
mv "${TAB}.new" "$TAB"
sysrc netwait_enable=YES
if [ -z "${netwait_ip:-}" ]; then
	netwait_ip=1.1.1.1
fi
if [ -z "${netwait_timeout:-}" ]; then
	netwait_timeout=60
fi
sysrc netwait_ip="$netwait_ip"
sysrc netwait_timeout="$netwait_timeout"
cat >> "$TAB" <<'EOF'
@reboot SHELL=/BSD/sh HOME=/home/green /usr/local/bin/screen -dmS grok-worker /BSD/sh /home/green/bin/grok-worker.sh
EOF
crontab -u green "$TAB"
echo "installed:"
crontab -u green -l
