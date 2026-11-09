#include <stdint.h>
#include <stddef.h>

extern void *elementold_lottie_create_data(const unsigned char *, long);
extern void elementold_lottie_destroy(void *);
extern long elementold_lottie_total_frames(void *);
extern double elementold_lottie_duration(void *);
extern void elementold_lottie_size(void *, long *, long *);
extern void elementold_lottie_render(void *, long, unsigned int *, long, long, long);

extern int elementold_video_to_animated_webp(
    const char *, const char *, int, int, int
);

extern int elementold_lottie_data_to_animated_webp(
    const unsigned char *, long, const char *, int, int
);

extern int elementold_webp_vertical_flip_copy(
    const char *, const char *
);

void *magnistra_lottie_create_data(const unsigned char *p, long n) {
    return elementold_lottie_create_data(p, n);
}

void magnistra_lottie_destroy(void *p) {
    elementold_lottie_destroy(p);
}

long magnistra_lottie_total_frames(void *p) {
    return elementold_lottie_total_frames(p);
}

double magnistra_lottie_duration(void *p) {
    return elementold_lottie_duration(p);
}

void magnistra_lottie_size(void *p, long *w, long *h) {
    elementold_lottie_size(p, w, h);
}

void magnistra_lottie_render(
    void *p,
    long frame,
    unsigned int *buffer,
    long width,
    long height,
    long stride
) {
    elementold_lottie_render(
        p,
        frame,
        buffer,
        width,
        height,
        stride
    );
}

int magnistra_video_to_animated_webp(
    const char *input,
    const char *output,
    int max_side,
    int fps,
    int max_frames
) {
    return elementold_video_to_animated_webp(
        input,
        output,
        max_side,
        fps,
        max_frames
    );
}

int magnistra_lottie_data_to_animated_webp(
    const unsigned char *data,
    long length,
    const char *output,
    int max_side,
    int max_frames
) {
    return elementold_lottie_data_to_animated_webp(
        data,
        length,
        output,
        max_side,
        max_frames
    );
}

int magnistra_webp_vertical_flip_copy(
    const char *input,
    const char *output
) {
    return elementold_webp_vertical_flip_copy(
        input,
        output
    );
}
