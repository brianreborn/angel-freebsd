#!/BSD/sh
# crontab @reboot starts this in a detached screen session named grok-worker.
# /etc/rc.d/netwait pings netwait_ip and returns when one host answers.
# onestart runs that check even if this boot already passed the rc step.
set -eu
export SHELL=/BSD/sh
export HOME=/home/green
/etc/rc.d/netwait onestart
cd /home/green
exec /home/green/.grok/bin/grok --continue
