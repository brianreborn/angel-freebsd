#include <unistd.h>

int
main(int argc, char **argv)
{
	argv[0] = "cc";
	execv("/host/usr/bin/cc", argv);
	return (127);
}
