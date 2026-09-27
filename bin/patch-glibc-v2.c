/*
 * NOP the glibc "CPU does not support x86-64-v2" fatal call.
 * The check is: if (!(isa_1 & V2)) _dl_fatal_printf(fmt, 2);
 * Leaving the call out falls through into the rest of ld.so startup.
 */
#include <err.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>

static const char needle[] = "CPU does not support x86-64-v";

static int
va_of(const unsigned char *elf, size_t len, size_t off, unsigned long *va)
{
	const unsigned char *e = elf;
	unsigned short phentsize;
	unsigned short phnum;
	unsigned long phoff;
	unsigned i;

	if (len < 64 || e[0] != 0x7f || e[1] != 'E' || e[2] != 'L' || e[3] != 'F')
		return (-1);
	phoff = *(const unsigned long *)(e + 32);
	phentsize = *(const unsigned short *)(e + 54);
	phnum = *(const unsigned short *)(e + 56);
	if (phentsize < 56 || phoff > len)
		return (-1);
	for (i = 0; i < phnum; i++) {
		size_t poff = phoff + (size_t)i * phentsize;
		unsigned int type;
		unsigned long p_offset, p_vaddr, p_filesz;

		if (poff + 56 > len)
			return (-1);
		type = *(const unsigned int *)(e + poff);
		if (type != 1)
			continue;
		p_offset = *(const unsigned long *)(e + poff + 8);
		p_vaddr = *(const unsigned long *)(e + poff + 16);
		p_filesz = *(const unsigned long *)(e + poff + 32);
		if (off >= p_offset && off < p_offset + p_filesz) {
			*va = p_vaddr + (off - p_offset);
			return (0);
		}
	}
	return (-1);
}

static int
off_of_va(const unsigned char *elf, size_t len, unsigned long va, size_t *off)
{
	const unsigned char *e = elf;
	unsigned short phentsize, phnum;
	unsigned long phoff;
	unsigned i;

	phoff = *(const unsigned long *)(e + 32);
	phentsize = *(const unsigned short *)(e + 54);
	phnum = *(const unsigned short *)(e + 56);
	for (i = 0; i < phnum; i++) {
		size_t poff = phoff + (size_t)i * phentsize;
		unsigned int type;
		unsigned long p_offset, p_vaddr, p_filesz;

		if (poff + 56 > len)
			return (-1);
		type = *(const unsigned int *)(e + poff);
		if (type != 1)
			continue;
		p_offset = *(const unsigned long *)(e + poff + 8);
		p_vaddr = *(const unsigned long *)(e + poff + 16);
		p_filesz = *(const unsigned long *)(e + poff + 32);
		if (va >= p_vaddr && va < p_vaddr + p_filesz) {
			*off = p_offset + (va - p_vaddr);
			return (0);
		}
	}
	return (-1);
}

static int
patch_one(const char *path)
{
	int fd, patched = 0;
	struct stat st;
	unsigned char *p;
	size_t i, nlen;

	fd = open(path, O_RDWR);
	if (fd < 0) {
		warn("%s", path);
		return (-1);
	}
	if (fstat(fd, &st) != 0 || st.st_size < 64) {
		close(fd);
		return (-1);
	}
	p = mmap(NULL, st.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (p == MAP_FAILED) {
		warn("mmap %s", path);
		close(fd);
		return (-1);
	}
	nlen = sizeof(needle) - 1;
	for (i = 0; i + nlen < (size_t)st.st_size; i++) {
		size_t j;
		unsigned long str_va;

		if (memcmp(p + i, needle, nlen) != 0)
			continue;
		if (va_of(p, st.st_size, i, &str_va) != 0)
			continue;
		/* lea rdi, [rip+disp32] is 7 bytes: 48 8d 3d xx xx xx xx */
		for (j = 0; j + 7 < (size_t)st.st_size; j++) {
			unsigned long insn_va, target;
			int disp;
			size_t k, call;

			if (p[j] != 0x48 || p[j + 1] != 0x8d || p[j + 2] != 0x3d)
				continue;
			if (va_of(p, st.st_size, j, &insn_va) != 0)
				continue;
			disp = *(int *)(p + j + 3);
			target = insn_va + 7 + (unsigned int)disp;
			if (target != str_va)
				continue;
			/* mov esi, 2  then the fatal call. Level 3 and 4 stay. */
			call = 0;
			for (k = j + 7; k + 5 < j + 32 && k + 5 < (size_t)st.st_size; k++) {
				if (p[k] == 0xbe && p[k + 1] == 0x02 &&
				    p[k + 2] == 0 && p[k + 3] == 0 && p[k + 4] == 0) {
					call = k + 5;
					break;
				}
			}
			if (call == 0 || p[call] != 0xe8)
				continue;
			if (p[call] == 0x90)
				continue;
			memset(p + call, 0x90, 5);
			printf("%s: nop fatal call at file offset %zu\n", path, call);
			patched++;
		}
	}
	munmap(p, st.st_size);
	close(fd);
	if (patched == 0)
		printf("%s: no v2 fatal call patched\n", path);
	return (patched);
}

int
main(int argc, char **argv)
{
	int i, n = 0;

	if (argc < 2)
		errx(1, "usage: patch-glibc-v2 ld-linux.so ...");
	for (i = 1; i < argc; i++)
		n += patch_one(argv[i]);
	if (n < 1)
		errx(1, "nothing patched");
	return (0);
}
