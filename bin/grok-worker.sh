#!/BSD/sh
# crontab @reboot starts this in a detached screen session named grok-worker.
# /etc/rc.d/netwait pings netwait_ip and returns when one host answers.
# onestart runs that check even if this boot already passed the rc step.
set -eu
export SHELL=/BSD/sh
export HOME=/home/green
export PATH=/BSD:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
/etc/rc.d/netwait onestart
cd /home/green
exec /home/green/.grok/bin/grok --continue
