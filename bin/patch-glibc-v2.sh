#!/BSD/sh
# NOP glibc's x86-64-v2 fatal call inside the Rocky loader.
set -eu
cd /home/green/bin
cc -O2 -o patch-glibc-v2 patch-glibc-v2.c
exec ./patch-glibc-v2 \
	/compat/linux/lib64/ld-linux-x86-64.so.2 \
	/compat/linux/usr/lib64/ld-linux-x86-64.so.2
