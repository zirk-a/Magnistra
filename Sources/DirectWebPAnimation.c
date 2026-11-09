#include <stddef.h>
#include <stdlib.h>
#include <stdint.h>
#include <webp/demux.h>

typedef struct {
    WebPAnimDecoder *decoder;
    int width;
    int height;
    int count;
} MGDirectWebPAnimation;

void *MagnistraDirectWebPAnimOpen(const uint8_t *bytes, size_t length,
                                  int32_t *width, int32_t *height, int32_t *frameCount) {
    if (!bytes || length < 16 || length > 4u * 1024u * 1024u ||
        !width || !height || !frameCount) return NULL;
    *width = 0; *height = 0; *frameCount = 0;
    WebPData source;
    source.bytes = bytes;
    source.size = length;
    WebPAnimDecoderOptions options;
    if (!WebPAnimDecoderOptionsInit(&options)) return NULL;
    options.use_threads = 0;

    options.color_mode = MODE_rgbA;
    WebPAnimDecoder *decoder = WebPAnimDecoderNew(&source, &options);
    if (!decoder) return NULL;
    WebPAnimInfo info;
    if (!WebPAnimDecoderGetInfo(decoder, &info) ||
        info.canvas_width == 0 || info.canvas_height == 0 ||
        info.canvas_width > 512 || info.canvas_height > 512 ||
        info.frame_count == 0 || info.frame_count > 400) {
        WebPAnimDecoderDelete(decoder);
        return NULL;
    }
    MGDirectWebPAnimation *state = (MGDirectWebPAnimation *)calloc(1, sizeof(*state));
    if (!state) { WebPAnimDecoderDelete(decoder); return NULL; }
    state->decoder = decoder;
    state->width = (int)info.canvas_width;
    state->height = (int)info.canvas_height;
    state->count = (int)info.frame_count;
    *width = (int32_t)state->width;
    *height = (int32_t)state->height;
    *frameCount = (int32_t)state->count;
    return state;
}

int32_t MagnistraDirectWebPAnimNext(void *handle,
                                    const uint8_t **pixels, int32_t *timestampMs) {
    if (!handle || !pixels || !timestampMs) return 0;
    MGDirectWebPAnimation *state = (MGDirectWebPAnimation *)handle;
    uint8_t *frame = NULL;
    int time = 0;
    if (!WebPAnimDecoderHasMoreFrames(state->decoder) ||
        !WebPAnimDecoderGetNext(state->decoder, &frame, &time) || !frame) return 0;
    *pixels = frame;
    *timestampMs = (int32_t)time;
    return 1;
}

void MagnistraDirectWebPAnimClose(void *handle) {
    if (!handle) return;
    MGDirectWebPAnimation *state = (MGDirectWebPAnimation *)handle;
    if (state->decoder) WebPAnimDecoderDelete(state->decoder);
    free(state);
}
