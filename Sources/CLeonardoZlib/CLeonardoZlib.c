#include "CLeonardoZlib.h"
#include <limits.h>
#include <string.h>
#include <zlib.h>

int leonardo_inflate(const uint8_t *input, size_t input_count, uint8_t *output,
                     size_t output_capacity, size_t *written, size_t *consumed) {
    if (!written || !consumed) return Z_STREAM_ERROR;
    *written = 0;
    *consumed = 0;
    if (!input || !output || input_count > UINT_MAX || output_capacity > UINT_MAX)
        return Z_STREAM_ERROR;
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_count;
    stream.next_out = output;
    stream.avail_out = (uInt)output_capacity;
    int result = inflateInit(&stream);
    if (result != Z_OK) return result;
    result = inflate(&stream, Z_FINISH);
    if (result == Z_STREAM_END) {
        *written = stream.total_out;
        *consumed = stream.total_in;
    }
    inflateEnd(&stream);
    return result;
}

size_t leonardo_compress_bound(size_t input_count) {
    if (input_count > UINT_MAX) return 0;
    return compressBound((uLong)input_count);
}

int leonardo_deflate(const uint8_t *input, size_t input_count, uint8_t *output,
                     size_t output_capacity, size_t *written) {
    if (!written || !output || input_count > UINT_MAX || output_capacity > UINT_MAX)
        return Z_STREAM_ERROR;
    const uint8_t empty = 0;
    if (!input && input_count != 0) return Z_STREAM_ERROR;
    uLongf size = output_capacity;
    int result = compress2(output, &size, input ? input : &empty, input_count, Z_DEFAULT_COMPRESSION);
    *written = result == Z_OK ? size : 0;
    return result;
}
