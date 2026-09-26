# Kernel module. Requires patch/trap-ud-hook.patch in the kernel
# before kldload. Build does not load the module.

KMOD=	amd64compat
SRCS=	amd64compat.c sse.S

.include <bsd.kmod.mk>
