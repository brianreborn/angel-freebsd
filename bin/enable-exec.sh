#!/BSD/sh
# Linux exec of /bin/sh opens /compat/linux/bin/sh first. That file is
# Rocky bash, and its glibc exits before main. Point it at /BSD/sh.
# /compat/linux/bin/bash stays the Rocky shell.
set -eu
if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: /BSD/sh $0" >&2
	exit 1
fi
if [ ! -x /BSD/sh ]; then
	echo "/BSD/sh is missing" >&2
	exit 1
fi
if [ ! -e /compat/linux/bin/sh.rocky ]; then
	mv /compat/linux/bin/sh /compat/linux/bin/sh.rocky
fi
ln -sfn /BSD/sh /compat/linux/bin/sh
# The grok tool execs bash. Rescue has no bash applet, and Rocky bash
# dies on the v2 check. Use the FreeBSD ports bash.
if [ -e /compat/linux/bin/bash ] && [ ! -e /compat/linux/bin/bash.rocky ]; then
	mv /compat/linux/bin/bash /compat/linux/bin/bash.rocky
fi
ln -sfn /usr/local/bin/bash /compat/linux/bin/bash
echo "sh -> $(readlink /compat/linux/bin/sh)"
echo "bash -> $(readlink /compat/linux/bin/bash)"
/compat/linux/bin/bash -c 'echo bash-ok; uname -s'
