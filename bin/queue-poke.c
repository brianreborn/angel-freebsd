/* Nonblocking write to a fifo. Exit 0 if a reader got the line. */
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int
main(int argc, char **argv)
{
	int fd;
	size_t n;

	if (argc != 3)
		return (2);
	fd = open(argv[1], O_WRONLY | O_NONBLOCK);
	if (fd < 0)
		return (1);
	n = strlen(argv[2]);
	if (write(fd, argv[2], n) != (ssize_t)n)
		return (1);
	return (0);
}
