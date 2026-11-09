#ifndef MAGNISTRA_GRID_FAST_DECODE_H
#define MAGNISTRA_GRID_FAST_DECODE_H
#include <stddef.h>

void *MagnistraGridDecodeBytes(const void *bytes, size_t length);
void *MagnistraGridDecodePath(const char *path);
#endif
