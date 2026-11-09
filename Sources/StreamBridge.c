#include "StreamBridge.h"

#include <curl/curl.h>
#include <pthread.h>
#include <stdlib.h>

typedef struct {
    CURL *easy;
    struct curl_slist *headers;
} MagnistraStreamBridgeHandle;

static pthread_once_t g_curl_once =
    PTHREAD_ONCE_INIT;

static int g_magnistra_curl_process_init_result = (int)CURLE_FAILED_INIT;
static void magnistra_stream_curl_global_init(void) {
    g_magnistra_curl_process_init_result = (int)curl_global_init(CURL_GLOBAL_DEFAULT);
}

int magnistra_curl_process_init_once(void) {
    pthread_once(&g_curl_once, magnistra_stream_curl_global_init);
    return g_magnistra_curl_process_init_result;
}

MagnistraStreamHandle magnistra_stream_bridge_init(void) {
    MagnistraStreamBridgeHandle *handle;

    pthread_once(
        &g_curl_once,
        magnistra_stream_curl_global_init
    );

    handle =
        (MagnistraStreamBridgeHandle *)
            calloc(
                1,
                sizeof(
                    MagnistraStreamBridgeHandle
                )
            );

    if (!handle) {
        return NULL;
    }

    handle->easy =
        curl_easy_init();

    if (!handle->easy) {
        free(handle);
        return NULL;
    }

    curl_easy_setopt(
        handle->easy,
        CURLOPT_NOSIGNAL,
        1L
    );

    curl_easy_setopt(
        handle->easy,
        CURLOPT_CONNECTTIMEOUT,
        20L
    );

    return handle;
}

void magnistra_stream_bridge_reset_for_image_reuse(MagnistraStreamHandle opaque) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;
    if (!handle || !handle->easy) return;
    curl_easy_reset(handle->easy);
    if (handle->headers) {
        curl_slist_free_all(handle->headers);
        handle->headers = NULL;
    }
    curl_easy_setopt(handle->easy, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(handle->easy, CURLOPT_CONNECTTIMEOUT, 20L);
}

void magnistra_stream_bridge_cleanup(
    MagnistraStreamHandle opaque
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    if (!handle) {
        return;
    }

    if (handle->headers) {
        curl_slist_free_all(
            handle->headers
        );
    }

    if (handle->easy) {
        curl_easy_cleanup(
            handle->easy
        );
    }

    free(handle);
}

void magnistra_stream_bridge_set_url(
    MagnistraStreamHandle opaque,
    const char *url
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    curl_easy_setopt(
        handle->easy,
        CURLOPT_URL,
        url
    );
}

void magnistra_stream_bridge_set_verified_ca(
    MagnistraStreamHandle opaque,
    const char *ca_path
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    curl_easy_setopt(
        handle->easy,
        CURLOPT_SSL_VERIFYPEER,
        1L
    );

    curl_easy_setopt(
        handle->easy,
        CURLOPT_SSL_VERIFYHOST,
        2L
    );

    curl_easy_setopt(
        handle->easy,
        CURLOPT_CAINFO,
        ca_path
    );
}

void magnistra_stream_bridge_set_follow_redirects(
    MagnistraStreamHandle opaque
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    curl_easy_setopt(
        handle->easy,
        CURLOPT_FOLLOWLOCATION,
        1L
    );

    curl_easy_setopt(
        handle->easy,
        CURLOPT_MAXREDIRS,
        5L
    );
}

void magnistra_stream_bridge_set_timeout(
    MagnistraStreamHandle opaque,
    long seconds
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    curl_easy_setopt(
        handle->easy,
        CURLOPT_TIMEOUT,
        seconds
    );
}

void magnistra_stream_bridge_set_stall_timeout(
    MagnistraStreamHandle opaque,
    long stall_seconds
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;
    if (!handle || !handle->easy || stall_seconds < 1L) return;
    curl_easy_setopt(handle->easy, CURLOPT_CONNECTTIMEOUT, 12L);
    curl_easy_setopt(handle->easy, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(handle->easy, CURLOPT_LOW_SPEED_TIME, stall_seconds);
}

void magnistra_stream_bridge_set_useragent(
    MagnistraStreamHandle opaque,
    const char *user_agent
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    curl_easy_setopt(
        handle->easy,
        CURLOPT_USERAGENT,
        user_agent
    );
}

void magnistra_stream_bridge_add_header(
    MagnistraStreamHandle opaque,
    const char *header
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    handle->headers =
        curl_slist_append(
            handle->headers,
            header
        );
}

void magnistra_stream_bridge_set_header_fn(
    MagnistraStreamHandle opaque,
    MagnistraStreamWriteFn fn,
    void *userdata
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    curl_easy_setopt(
        handle->easy,
        CURLOPT_HEADERFUNCTION,
        fn
    );

    curl_easy_setopt(
        handle->easy,
        CURLOPT_HEADERDATA,
        userdata
    );
}

void magnistra_stream_bridge_set_write_fn(
    MagnistraStreamHandle opaque,
    MagnistraStreamWriteFn fn,
    void *userdata
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    curl_easy_setopt(
        handle->easy,
        CURLOPT_WRITEFUNCTION,
        fn
    );

    curl_easy_setopt(
        handle->easy,
        CURLOPT_WRITEDATA,
        userdata
    );
}

void magnistra_stream_bridge_set_progress_fn(
    MagnistraStreamHandle opaque,
    MagnistraStreamProgressFn fn,
    void *userdata
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    curl_easy_setopt(
        handle->easy,
        CURLOPT_NOPROGRESS,
        0L
    );

    curl_easy_setopt(
        handle->easy,
        CURLOPT_XFERINFOFUNCTION,
        fn
    );

    curl_easy_setopt(
        handle->easy,
        CURLOPT_XFERINFODATA,
        userdata
    );
}

int magnistra_stream_bridge_perform(
    MagnistraStreamHandle opaque
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    if (handle->headers) {
        curl_easy_setopt(
            handle->easy,
            CURLOPT_HTTPHEADER,
            handle->headers
        );
    }

    return (int)
        curl_easy_perform(
            handle->easy
        );
}

long magnistra_stream_bridge_response_code(
    MagnistraStreamHandle opaque
) {
    MagnistraStreamBridgeHandle *handle =
        (MagnistraStreamBridgeHandle *)opaque;

    long code = 0;

    curl_easy_getinfo(
        handle->easy,
        CURLINFO_RESPONSE_CODE,
        &code
    );

    return code;
}
