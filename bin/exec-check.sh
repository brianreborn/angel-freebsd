#!/BSD/sh
# Record how /bin/sh resolves, for the grok tool that still cannot spawn.
set -eu
OUT=/home/green/exec-check.txt
{
	echo "=== links ==="
	ls -ld /compat/linux/bin/sh /compat/linux/bin/sh.rocky /BSD /BSD/sh /rescue/sh
	echo "readlink sh: $(readlink /compat/linux/bin/sh || true)"
	echo "=== run via compat path ==="
	/compat/linux/bin/sh -c 'echo from-compat-sh; uname -s; echo $0'
	echo "=== run /bin/sh ==="
	/bin/sh -c 'echo from-bin-sh; uname -s'
	echo "=== exit ok ==="
} > "$OUT" 2>&1
echo "wrote $OUT"
