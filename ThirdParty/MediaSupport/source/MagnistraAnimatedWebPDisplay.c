#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <webp/encode.h>
#include <webp/mux.h>
#include <webp/demux.h>

extern void *elementold_lottie_create_data(const unsigned char *bytes, long length);
extern void elementold_lottie_destroy(void *opaque);
extern long elementold_lottie_total_frames(void *opaque);
extern double elementold_lottie_duration(void *opaque);
extern void elementold_lottie_size(void *opaque, long *width, long *height);
extern void elementold_lottie_render(void *opaque, long frame,
                                     unsigned int *buffer,
                                     long width, long height, long stride);

static void eo_unpremultiply_bgra(uint8_t *p, size_t pixels) {
    size_t i;
    for (i = 0; i < pixels; ++i, p += 4) {
        const unsigned int a = p[3];
        if (a == 0) {
            p[0] = p[1] = p[2] = 0;
        } else if (a < 255) {
            unsigned int b = ((unsigned int)p[0] * 255u + a / 2u) / a;
            unsigned int g = ((unsigned int)p[1] * 255u + a / 2u) / a;
            unsigned int r = ((unsigned int)p[2] * 255u + a / 2u) / a;
            p[0] = (uint8_t)(b > 255u ? 255u : b);
            p[1] = (uint8_t)(g > 255u ? 255u : g);
            p[2] = (uint8_t)(r > 255u ? 255u : r);
        }
    }
}

static int eo_write_anim(WebPAnimEncoder *enc, int final_timestamp,
                         const char *output_path, int written) {
    WebPData data;
    int assembled;
    FILE *f;
    if (written < 2) return -30;
    if (final_timestamp < 1) final_timestamp = 1;
    if (!WebPAnimEncoderAdd(enc, NULL, final_timestamp, NULL)) return -31;
    WebPDataInit(&data);
    assembled = WebPAnimEncoderAssemble(enc, &data);
    if (!assembled || data.bytes == NULL || data.size == 0) {
        WebPDataClear(&data);
        return -32;
    }
    f = fopen(output_path, "wb");
    if (!f) {
        WebPDataClear(&data);
        return -33;
    }
    if (fwrite(data.bytes, 1, data.size, f) != data.size) {
        fclose(f);
        WebPDataClear(&data);
        return -34;
    }
    fclose(f);
    WebPDataClear(&data);
    return written;
}

int elementold_lottie_data_to_animated_webp(const unsigned char *bytes,
                                              long length,
                                              const char *output_path,
                                              int max_side,
                                              int max_frames) {
    void *animation = NULL;
    long source_w = 0, source_h = 0, total = 0;
    int width, height, output_count, i, written = 0;
    double duration, scale = 1.0;
    uint32_t *pixels = NULL;
    WebPAnimEncoderOptions anim_options;
    WebPAnimEncoder *enc = NULL;
    WebPConfig config;

    if (!bytes || length <= 0 || !output_path || max_side < 32 || max_frames < 2)
        return -10;

    animation = elementold_lottie_create_data(bytes, length);
    if (!animation) return -11;

    total = elementold_lottie_total_frames(animation);
    duration = elementold_lottie_duration(animation);
    elementold_lottie_size(animation, &source_w, &source_h);
    if (total < 2 || source_w <= 0 || source_h <= 0) {
        elementold_lottie_destroy(animation);
        return -12;
    }
    if (!(duration > 0.0) || duration > 60.0)
        duration = (double)total / 30.0;

    if (source_w > source_h) {
        if (source_w > max_side) scale = (double)max_side / (double)source_w;
    } else {
        if (source_h > max_side) scale = (double)max_side / (double)source_h;
    }
    width = (int)((double)source_w * scale + 0.5);
    height = (int)((double)source_h * scale + 0.5);
    if (width < 1) width = 1;
    if (height < 1) height = 1;

    output_count = total < max_frames ? (int)total : max_frames;
    if (output_count < 2) output_count = 2;

    if (!WebPAnimEncoderOptionsInit(&anim_options)) {
        elementold_lottie_destroy(animation);
        return -13;
    }
    anim_options.anim_params.loop_count = 0;
    anim_options.minimize_size = 1;
    enc = WebPAnimEncoderNew(width, height, &anim_options);
    if (!enc) {
        elementold_lottie_destroy(animation);
        return -14;
    }
    if (!WebPConfigInit(&config)) {
        WebPAnimEncoderDelete(enc);
        elementold_lottie_destroy(animation);
        return -15;
    }
    config.lossless = 1;
    config.quality = 100.0f;
    config.method = 3;
    config.alpha_quality = 100;

    pixels = (uint32_t *)calloc((size_t)width * (size_t)height, 4u);
    if (!pixels) {
        WebPAnimEncoderDelete(enc);
        elementold_lottie_destroy(animation);
        return -16;
    }

    for (i = 0; i < output_count; ++i) {
        long source_frame;
        int timestamp;
        WebPPicture pic;
        int ok;

        if (output_count <= 1) source_frame = 0;
        else source_frame = (long)(((long long)(total - 1) * i) / (output_count - 1));

        memset(pixels, 0, (size_t)width * (size_t)height * 4u);
        elementold_lottie_render(animation, source_frame, pixels,
                                 width, height, width * 4);
        eo_unpremultiply_bgra((uint8_t *)pixels, (size_t)width * (size_t)height);

        if (!WebPPictureInit(&pic)) continue;
        pic.width = width;
        pic.height = height;
        ok = WebPPictureImportBGRA(&pic, (const uint8_t *)pixels, width * 4);
        if (!ok) {
            WebPPictureFree(&pic);
            continue;
        }

        timestamp = (int)(duration * 1000.0 * (double)i / (double)output_count + 0.5);
        ok = WebPAnimEncoderAdd(enc, &pic, timestamp, &config);
        WebPPictureFree(&pic);
        if (!ok) continue;
        ++written;
    }

    free(pixels);
    pixels = NULL;
    elementold_lottie_destroy(animation);

    {
        int final_timestamp = (int)(duration * 1000.0 + 0.5);
        int rc = eo_write_anim(enc, final_timestamp, output_path, written);
        WebPAnimEncoderDelete(enc);
        return rc;
    }
}

static uint8_t *eo_read_file(const char *path, size_t *size_out) {
    FILE *f;
    long n;
    uint8_t *data;
    if (!path || !size_out) return NULL;
    f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    n = ftell(f);
    if (n <= 0 || fseek(f, 0, SEEK_SET) != 0) { fclose(f); return NULL; }
    data = (uint8_t *)malloc((size_t)n);
    if (!data) { fclose(f); return NULL; }
    if (fread(data, 1, (size_t)n, f) != (size_t)n) {
        free(data); fclose(f); return NULL;
    }
    fclose(f);
    *size_out = (size_t)n;
    return data;
}

int elementold_webp_vertical_flip_copy(const char *input_path,
                                        const char *output_path) {
    size_t source_size = 0;
    uint8_t *source = NULL;
    WebPData webp_data;
    WebPAnimDecoderOptions dec_options;
    WebPAnimDecoder *dec = NULL;
    WebPAnimInfo info;
    WebPAnimEncoderOptions enc_options;
    WebPAnimEncoder *enc = NULL;
    WebPConfig config;
    uint8_t *flipped = NULL;
    int written = 0, previous_end = 0;

    if (!input_path || !output_path) return -40;
    source = eo_read_file(input_path, &source_size);
    if (!source) return -41;

    WebPDataInit(&webp_data);
    webp_data.bytes = source;
    webp_data.size = source_size;

    if (!WebPAnimDecoderOptionsInit(&dec_options)) { free(source); return -42; }
    dec_options.color_mode = MODE_BGRA;
    dec_options.use_threads = 0;
    dec = WebPAnimDecoderNew(&webp_data, &dec_options);
    if (!dec) { free(source); return -43; }
    if (!WebPAnimDecoderGetInfo(dec, &info) || info.frame_count < 2) {
        WebPAnimDecoderDelete(dec); free(source); return -44;
    }

    if (!WebPAnimEncoderOptionsInit(&enc_options)) {
        WebPAnimDecoderDelete(dec); free(source); return -45;
    }
    enc_options.anim_params.loop_count = info.loop_count;
    enc_options.anim_params.bgcolor = info.bgcolor;
    enc_options.minimize_size = 1;
    enc = WebPAnimEncoderNew((int)info.canvas_width, (int)info.canvas_height, &enc_options);
    if (!enc) { WebPAnimDecoderDelete(dec); free(source); return -46; }
    if (!WebPConfigInit(&config)) {
        WebPAnimEncoderDelete(enc); WebPAnimDecoderDelete(dec); free(source); return -47;
    }
    config.lossless = 1;
    config.quality = 100.0f;
    config.method = 3;
    config.alpha_quality = 100;

    flipped = (uint8_t *)malloc((size_t)info.canvas_width * (size_t)info.canvas_height * 4u);
    if (!flipped) {
        WebPAnimEncoderDelete(enc); WebPAnimDecoderDelete(dec); free(source); return -48;
    }

    while (WebPAnimDecoderHasMoreFrames(dec)) {
        uint8_t *frame = NULL;
        int end_timestamp = 0;
        int y;
        WebPPicture pic;
        int ok;
        const int stride = (int)info.canvas_width * 4;

        if (!WebPAnimDecoderGetNext(dec, &frame, &end_timestamp) || !frame) break;
        for (y = 0; y < (int)info.canvas_height; ++y) {
            memcpy(flipped + (size_t)y * (size_t)stride,
                   frame + (size_t)((int)info.canvas_height - 1 - y) * (size_t)stride,
                   (size_t)stride);
        }

        if (!WebPPictureInit(&pic)) continue;
        pic.width = (int)info.canvas_width;
        pic.height = (int)info.canvas_height;
        ok = WebPPictureImportBGRA(&pic, flipped, stride);
        if (!ok) { WebPPictureFree(&pic); continue; }
        ok = WebPAnimEncoderAdd(enc, &pic, previous_end, &config);
        WebPPictureFree(&pic);
        if (!ok) continue;
        previous_end = end_timestamp > previous_end ? end_timestamp : previous_end + 1;
        ++written;
    }

    free(flipped);
    WebPAnimDecoderDelete(dec);
    free(source);

    {
        int rc = eo_write_anim(enc, previous_end, output_path, written);
        WebPAnimEncoderDelete(enc);
        return rc;
    }
}
