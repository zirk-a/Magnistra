#include <stddef.h>
#include <errno.h>

__attribute__((used, noinline, visibility("default")))
int memset_s(void *dest, size_t destsz, int ch, size_t count)
{
    if (dest == NULL || destsz == 0) return EINVAL;
    size_t to_write = count <= destsz ? count : destsz;
    volatile unsigned char *p = (volatile unsigned char *) dest;
    for (size_t i = 0; i < to_write; i++) {
        p[i] = (unsigned char) ch;
    }
    __asm__ __volatile__("" : : "r"(dest) : "memory");
    return count <= destsz ? 0 : EINVAL;
}
