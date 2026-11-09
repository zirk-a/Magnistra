#include "GridFastDecode.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <sys/sysctl.h>
#include <stdint.h>
#include <string.h>
#include <limits.h>
#include <stdbool.h>

static size_t MagnistraGridMaxDimension(void) {
    uint64_t memoryBytes = 0;
    size_t length = sizeof(memoryBytes);
    if (sysctlbyname("hw.memsize", &memoryBytes, &length, NULL, 0) != 0 || memoryBytes == 0)
        return 768;
    if (memoryBytes <= 300ULL * 1024ULL * 1024ULL) return 640;
    if (memoryBytes <= 600ULL * 1024ULL * 1024ULL) return 768;
    return 1024;
}

static CFDictionaryRef MagnistraImageSourceOptions(void) {
    CFMutableDictionaryRef options = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (options)
        CFDictionarySetValue(options, kCGImageSourceShouldCache, kCFBooleanFalse);
    return options;
}

static void *MagnistraGridImageFromSource(CGImageSourceRef source) {
    if (!source) return NULL;
    CFMutableDictionaryRef options = CFDictionaryCreateMutable(kCFAllocatorDefault, 3,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!options) return NULL;
    CFDictionarySetValue(options, kCGImageSourceCreateThumbnailFromImageAlways, kCFBooleanTrue);
    CFDictionarySetValue(options, kCGImageSourceCreateThumbnailWithTransform, kCFBooleanTrue);
    int dim = (int)MagnistraGridMaxDimension();
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &dim);
    if (!number) { CFRelease(options); return NULL; }
    CFDictionarySetValue(options, kCGImageSourceThumbnailMaxPixelSize, number);
    CFRelease(number);
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, options);
    CFRelease(options);
    if (!image) return NULL;
    Class imageClass = objc_getClass("UIImage");
    if (!imageClass) { CGImageRelease(image); return NULL; }

    id uiImage = ((id (*)(id, SEL, CGImageRef))objc_msgSend)(
        (id)imageClass, sel_registerName("imageWithCGImage:"), image);
    CGImageRelease(image);
    if (!uiImage) return NULL;
    id retainedImage = ((id (*)(id, SEL))objc_msgSend)(uiImage, sel_registerName("retain"));
    return (void *)retainedImage;
}

void *MagnistraGridDecodeBytes(const void *bytes, size_t length) {
    if (!bytes || !length || length > (size_t)LONG_MAX) return NULL;

    CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,
        (const UInt8 *)bytes, (CFIndex)length, kCFAllocatorNull);
    if (!data) return NULL;
    CFDictionaryRef options = MagnistraImageSourceOptions();
    CGImageSourceRef source = CGImageSourceCreateWithData(data, options);
    if (options) CFRelease(options);
    CFRelease(data);
    if (!source) return NULL;
    void *image = MagnistraGridImageFromSource(source);
    CFRelease(source);
    return image;
}

void *MagnistraGridDecodePath(const char *path) {
    if (!path || !path[0]) return NULL;
    size_t length = strlen(path);
    if (length > (size_t)LONG_MAX) return NULL;
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
        (const UInt8 *)path, (CFIndex)length, false);
    if (!url) return NULL;
    CFDictionaryRef options = MagnistraImageSourceOptions();
    CGImageSourceRef source = CGImageSourceCreateWithURL(url, options);
    if (options) CFRelease(options);
    CFRelease(url);
    if (!source) return NULL;
    void *image = MagnistraGridImageFromSource(source);
    CFRelease(source);
    return image;
}
