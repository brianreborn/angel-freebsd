#!/BSD/sh
# crontab @reboot starts this in a detached screen session named grok-worker.
# /etc/rc.d/netwait pings netwait_ip and returns when one host answers.
# onestart runs that check even if this boot already passed the rc step.
set -eu
export SHELL=/BSD/sh
export HOME=/home/green
export PATH=/home/green/.grok/bin:/BSD:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
/etc/rc.d/netwait onestart
cd /home/green
# This session, not whichever chat happens to be newest.
exec grok --resume 01a0ddcd-953a-7f02-963f-1214112e9835 -p "The machine just booted. Continue the current task. Do not wait for input."
