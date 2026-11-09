#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <webp/encode.h>
#import <webp/mux.h>

static int eo_copy_rgba(CGImageRef image, int width, int height,
                        uint8_t **out_pixels, size_t *out_stride) {
    if (image == NULL || width <= 0 || height <= 0 ||
        out_pixels == NULL || out_stride == NULL) return 0;

    const size_t stride = (size_t)width * 4u;
    uint8_t *pixels = (uint8_t *)calloc((size_t)height, stride);
    if (pixels == NULL) return 0;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    if (cs == NULL) { free(pixels); return 0; }

    CGBitmapInfo info = (CGBitmapInfo)(kCGImageAlphaPremultipliedLast |
                                      kCGBitmapByteOrder32Big);
    CGContextRef ctx = CGBitmapContextCreate(pixels, width, height, 8,
                                             stride, cs, info);
    CGColorSpaceRelease(cs);
    if (ctx == NULL) { free(pixels); return 0; }

    CGContextTranslateCTM(ctx, 0, height);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), image);
    CGContextRelease(ctx);

    *out_pixels = pixels;
    *out_stride = stride;
    return 1;
}

int elementold_video_to_animated_webp(const char *input_path,
                                      const char *output_path,
                                      int max_side,
                                      int fps,
                                      int max_frames) {
    if (input_path == NULL || output_path == NULL ||
        max_side < 32 || fps < 1 || max_frames < 2) return 0;

    @autoreleasepool {
        NSString *input = [NSString stringWithUTF8String:input_path];
        NSString *output = [NSString stringWithUTF8String:output_path];
        if (input == nil || output == nil) return 0;

        NSURL *url = [NSURL fileURLWithPath:input];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        if ([[asset tracksWithMediaType:AVMediaTypeVideo] count] < 1) return 0;

        const double seconds = CMTimeGetSeconds(asset.duration);
        if (!isfinite(seconds) || seconds <= 0.0 || seconds > 90.0) return 0;

        int desired = (int)ceil(seconds * (double)fps);
        if (desired < 2) desired = 2;
        int frame_count = desired < max_frames ? desired : max_frames;
        if (frame_count < 2) return 0;

        AVAssetImageGenerator *gen =
            [[AVAssetImageGenerator alloc] initWithAsset:asset];
        gen.appliesPreferredTrackTransform = YES;
        gen.maximumSize = CGSizeMake((CGFloat)max_side, (CGFloat)max_side);

        NSError *first_error = nil;
        CMTime actual = kCMTimeZero;
        CGImageRef first = [gen copyCGImageAtTime:kCMTimeZero
                                      actualTime:&actual
                                           error:&first_error];
        if (first == NULL) return 0;

        const int width = (int)CGImageGetWidth(first);
        const int height = (int)CGImageGetHeight(first);
        if (width <= 0 || height <= 0 || width > max_side || height > max_side) {
            CGImageRelease(first);
            return 0;
        }

        WebPAnimEncoderOptions anim_options;
        if (!WebPAnimEncoderOptionsInit(&anim_options)) {
            CGImageRelease(first);
            return 0;
        }
        anim_options.anim_params.loop_count = 0;
        anim_options.minimize_size = 1;

        WebPAnimEncoder *enc =
            WebPAnimEncoderNew(width, height, &anim_options);
        if (enc == NULL) {
            CGImageRelease(first);
            return 0;
        }

        WebPConfig config;
        if (!WebPConfigInit(&config)) {
            WebPAnimEncoderDelete(enc);
            CGImageRelease(first);
            return 0;
        }
        config.lossless = 0;
        config.quality = 72.0f;
        config.method = 3;
        config.alpha_quality = 90;

        int written = 0;
        int last_timestamp = 0;
        for (int i = 0; i < frame_count; ++i) {
            @autoreleasepool {
                CGImageRef cg = NULL;
                if (i == 0) {
                    cg = first;
                    CFRetain(cg);
                } else {
                    const double pos = seconds * (double)i / (double)frame_count;
                    CMTime req = CMTimeMakeWithSeconds(pos, 600);
                    NSError *err = nil;
                    CMTime got = kCMTimeZero;
                    cg = [gen copyCGImageAtTime:req actualTime:&got error:&err];
                }
                if (cg == NULL) continue;

                uint8_t *rgba = NULL;
                size_t stride = 0;
                if (!eo_copy_rgba(cg, width, height, &rgba, &stride)) {
                    CGImageRelease(cg);
                    continue;
                }

                WebPPicture pic;
                if (!WebPPictureInit(&pic)) {
                    free(rgba);
                    CGImageRelease(cg);
                    continue;
                }
                pic.width = width;
                pic.height = height;

                const int imported =
                    WebPPictureImportRGBA(&pic, rgba, (int)stride);
                free(rgba);
                CGImageRelease(cg);
                if (!imported) {
                    WebPPictureFree(&pic);
                    continue;
                }

                int timestamp =
                    (int)llround(seconds * 1000.0 * (double)i /
                                 (double)frame_count);
                if (timestamp <= last_timestamp && written > 0)
                    timestamp = last_timestamp + 1;

                const int ok =
                    WebPAnimEncoderAdd(enc, &pic, timestamp, &config);
                WebPPictureFree(&pic);
                if (!ok) continue;

                last_timestamp = timestamp;
                ++written;
            }
        }
        CGImageRelease(first);

        if (written < 2) {
            WebPAnimEncoderDelete(enc);
            return 0;
        }

        int final_timestamp = (int)llround(seconds * 1000.0);
        if (final_timestamp <= last_timestamp)
            final_timestamp = last_timestamp + 1;

        if (!WebPAnimEncoderAdd(enc, NULL, final_timestamp, NULL)) {
            WebPAnimEncoderDelete(enc);
            return 0;
        }

        WebPData data;
        WebPDataInit(&data);
        const int assembled = WebPAnimEncoderAssemble(enc, &data);
        WebPAnimEncoderDelete(enc);
        if (!assembled || data.bytes == NULL || data.size == 0) {
            WebPDataClear(&data);
            return 0;
        }

        NSData *encoded = [NSData dataWithBytes:data.bytes length:data.size];
        WebPDataClear(&data);
        if (encoded == nil) return 0;

        [[NSFileManager defaultManager] removeItemAtPath:output error:nil];
        return [encoded writeToFile:output atomically:YES] ? written : 0;
    }
}
