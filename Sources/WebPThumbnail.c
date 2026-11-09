#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include "webp/decode.h"

int32_t MagnistraWebPDecodeThumbnailRGBA(const uint8_t *input,
                                        size_t input_length,
                                        int32_t max_edge,
                                        uint8_t **output,
                                        int32_t *out_width,
                                        int32_t *out_height) {
  WebPBitstreamFeatures features;
  WebPDecoderConfig config;
  int w, h;
  int64_t width64, height64, total;
  uint8_t *pixels;
  size_t length;
  VP8StatusCode status;
  if (output == NULL || out_width == NULL || out_height == NULL) return 0;
  *output = NULL;
  *out_width = *out_height = 0;
  if (input == NULL || input_length < 12 || input_length > 16u * 1024u * 1024u ||
      max_edge < 32 || max_edge > 1024) return 0;
  if (WebPGetFeatures(input, input_length, &features) != VP8_STATUS_OK) return 0;
  if (features.width < 1 || features.height < 1 ||
      features.width > 16384 || features.height > 16384) return 0;
  if ((int64_t)features.width * features.height > 100000000LL) return 0;
  w = features.width;
  h = features.height;
  if (w > max_edge || h > max_edge) {
    if (w >= h) {
      height64 = ((int64_t)h * max_edge) / w;
      w = max_edge;
      h = (int)(height64 > 0 ? height64 : 1);
    } else {
      width64 = ((int64_t)w * max_edge) / h;
      h = max_edge;
      w = (int)(width64 > 0 ? width64 : 1);
    }
  }
  total = (int64_t)w * h * 4;
  if (total < 1 || total > 1024LL * 1024LL * 4) return 0;
  length = (size_t)total;
  pixels = (uint8_t *)malloc(length);
  if (pixels == NULL) return 0;
  if (!WebPInitDecoderConfig(&config)) {
    free(pixels);
    return 0;
  }
  config.options.use_scaling = 1;
  config.options.scaled_width = w;
  config.options.scaled_height = h;
  config.output.colorspace = MODE_RGBA;
  config.output.is_external_memory = 1;
  config.output.u.RGBA.rgba = pixels;
  config.output.u.RGBA.stride = w * 4;
  config.output.u.RGBA.size = length;
  status = WebPDecode(input, input_length, &config);
  WebPFreeDecBuffer(&config.output);
  if (status != VP8_STATUS_OK) {
    free(pixels);
    return 0;
  }
  *output = pixels;
  *out_width = (int32_t)w;
  *out_height = (int32_t)h;
  return 1;
}

void MagnistraWebPFreeThumbnail(uint8_t *pixels) { free(pixels); }
