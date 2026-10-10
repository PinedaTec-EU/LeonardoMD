#ifndef LEONARDO_ZLIB_H
#define LEONARDO_ZLIB_H
#include <stddef.h>
#include <stdint.h>
int leonardo_inflate(const uint8_t *input, size_t input_count, uint8_t *output,
                     size_t output_capacity, size_t *written, size_t *consumed);
size_t leonardo_compress_bound(size_t input_count);
int leonardo_deflate(const uint8_t *input, size_t input_count, uint8_t *output,
                     size_t output_capacity, size_t *written);
#endif
