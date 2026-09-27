/*
 * Block until stdin has a line, or someone writes the kick fifo.
 * Prints "key <line>" or "kick".
 */
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/select.h>

int
main(int argc, char **argv)
{
	int kfd, n;
	fd_set rfds;
	char buf[512];

	if (argc != 2)
		errx(2, "usage: queue-block kickfifo");
	kfd = open(argv[1], O_RDWR | O_NONBLOCK);
	if (kfd < 0)
		err(1, "%s", argv[1]);
	for (;;) {
		FD_ZERO(&rfds);
		FD_SET(STDIN_FILENO, &rfds);
		FD_SET(kfd, &rfds);
		n = select(kfd + 1, &rfds, NULL, NULL, NULL);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			err(1, "select");
		}
		if (FD_ISSET(kfd, &rfds)) {
			/* Drain. A kick only means "look again". */
			while (read(kfd, buf, sizeof(buf)) > 0)
				;
			printf("kick\n");
			fflush(stdout);
			return (0);
		}
		if (FD_ISSET(STDIN_FILENO, &rfds)) {
			if (fgets(buf, sizeof(buf), stdin) == NULL)
				return (1);
			buf[strcspn(buf, "\n")] = '\0';
			printf("key %s\n", buf);
			fflush(stdout);
			return (0);
		}
	}
}
