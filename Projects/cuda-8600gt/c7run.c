/*
 * User chroot into the local CentOS 7 tree, then exec a path inside it.
 * Requires security.bsd.unprivileged_chroot=1 (one host switch) and sets
 * PROC_NO_NEW_PRIVS, which this kernel demands for an unprivileged chroot.
 * Does not change compat.linux.emul_path. Inside the chroot, namei of
 * /compat/linux is this tree, so ld-linux is the CentOS 7 one.
 */
#include <err.h>
#include <unistd.h>
#include <sys/procctl.h>

int
main(int argc, char **argv)
{
	int enable;

	if (argc < 3) {
		errx(2, "usage: c7run jail-path /program-inside [args...]");
	}

	enable = PROC_NO_NEW_PRIVS_ENABLE;
	if (procctl(P_PID, 0, PROC_NO_NEW_PRIVS_CTL, &enable) != 0)
		err(1, "procctl PROC_NO_NEW_PRIVS");
	if (chroot(argv[1]) != 0)
		err(1, "chroot %s (sysctl security.bsd.unprivileged_chroot=1)",
		    argv[1]);
	if (chdir("/") != 0)
		err(1, "chdir");

	execv(argv[2], argv + 2);
	err(1, "exec %s", argv[2]);
}
