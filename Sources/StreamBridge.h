#ifndef MAGNISTRA_STREAM_BRIDGE_H
#define MAGNISTRA_STREAM_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *MagnistraStreamHandle;

typedef size_t (*MagnistraStreamWriteFn)(
    const void *ptr,
    size_t size,
    size_t nmemb,
    void *userdata
);

typedef int (*MagnistraStreamProgressFn)(
    void *userdata,
    int64_t dltotal,
    int64_t dlnow,
    int64_t ultotal,
    int64_t ulnow
);

MagnistraStreamHandle magnistra_stream_bridge_init(void);
void magnistra_stream_bridge_cleanup(MagnistraStreamHandle handle);
void magnistra_stream_bridge_reset_for_image_reuse(MagnistraStreamHandle handle);

void magnistra_stream_bridge_set_url(
    MagnistraStreamHandle handle,
    const char *url
);

void magnistra_stream_bridge_set_verified_ca(
    MagnistraStreamHandle handle,
    const char *ca_path
);

void magnistra_stream_bridge_set_follow_redirects(
    MagnistraStreamHandle handle
);

void magnistra_stream_bridge_set_stall_timeout(
    MagnistraStreamHandle handle,
    long stall_seconds
);

void magnistra_stream_bridge_set_timeout(
    MagnistraStreamHandle handle,
    long seconds
);

void magnistra_stream_bridge_set_useragent(
    MagnistraStreamHandle handle,
    const char *user_agent
);

void magnistra_stream_bridge_add_header(
    MagnistraStreamHandle handle,
    const char *header
);

void magnistra_stream_bridge_set_header_fn(
    MagnistraStreamHandle handle,
    MagnistraStreamWriteFn fn,
    void *userdata
);

void magnistra_stream_bridge_set_write_fn(
    MagnistraStreamHandle handle,
    MagnistraStreamWriteFn fn,
    void *userdata
);

void magnistra_stream_bridge_set_progress_fn(
    MagnistraStreamHandle handle,
    MagnistraStreamProgressFn fn,
    void *userdata
);

int magnistra_stream_bridge_perform(
    MagnistraStreamHandle handle
);

long magnistra_stream_bridge_response_code(
    MagnistraStreamHandle handle
);

#ifdef __cplusplus
}
#endif

#endif
