#include "ReelsTransport.h"

#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int magnistra_curl_process_init_once(void);
#ifdef curl_global_init
#undef curl_global_init
#endif
#ifdef curl_global_cleanup
#undef curl_global_cleanup
#endif
#define curl_global_init(...) ((CURLcode)magnistra_curl_process_init_once())
#define curl_global_cleanup() ((void)0)

typedef struct {
    unsigned char *data;
    size_t size;
    size_t capacity;
} MagnistraExploreBuffer;

static MagnistraExploreBuffer g_body = { NULL, 0, 0 };
static long g_status = 0;
static long g_verify = -1;

static void reset_state(void) {
    if (g_body.data) {
        free(g_body.data);
    }

    g_body.data = NULL;
    g_body.size = 0;
    g_body.capacity = 0;
    g_status = 0;
    g_verify = -1;
}

static size_t write_body(
    char *ptr,
    size_t size,
    size_t nmemb,
    void *userdata
) {
    MagnistraExploreBuffer *buffer =
        (MagnistraExploreBuffer *)userdata;

    size_t incoming =
        size * nmemb;

    if (!incoming) {
        return 0;
    }

    size_t wanted =
        buffer->size +
        incoming +
        1;

    if (wanted > buffer->capacity) {
        size_t next =
            buffer->capacity
                ? buffer->capacity
                : 4096;

        while (next < wanted) {
            next *= 2;
        }

        unsigned char *grown =
            (unsigned char *)realloc(
                buffer->data,
                next
            );

        if (!grown) {
            return 0;
        }

        buffer->data = grown;
        buffer->capacity = next;
    }

    memcpy(
        buffer->data + buffer->size,
        ptr,
        incoming
    );

    buffer->size += incoming;
    buffer->data[buffer->size] = 0;

    return incoming;
}

int magnistra_reels_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *max_id
) {
    CURL *easy = NULL;
    CURLcode rc;
    struct curl_slist *headers = NULL;

    char url[4096];
    char lang_header[512];
    char csrf_header[1024];
    char *escaped_cursor = NULL;

    reset_state();

    if (
        !ca_path ||
        !ca_path[0] ||
        !user_agent ||
        !user_agent[0] ||
        !cookie_header ||
        !cookie_header[0] ||
        !csrf_token ||
        !csrf_token[0]
    ) {
        return -6400;
    }

    rc =
        curl_global_init(
            CURL_GLOBAL_DEFAULT
        );

    if (rc != CURLE_OK) {
        return (int)rc;
    }

    easy =
        curl_easy_init();

    if (!easy) {
        curl_global_cleanup();
        return -6401;
    }

    if (
        max_id &&
        max_id[0]
    ) {
        escaped_cursor =
            curl_easy_escape(
                easy,
                max_id,
                0
            );
    }

    if (
        escaped_cursor &&
        escaped_cursor[0]
    ) {
        snprintf(
            url,
            sizeof(url),
            "https://www.instagram.com/api/v1/clips/discover/?max_id=%s",
            escaped_cursor
        );
    } else {
        snprintf(
            url,
            sizeof(url),
            "https://www.instagram.com/api/v1/clips/discover/"
        );
    }

    snprintf(
        lang_header,
        sizeof(lang_header),
        "Accept-Language: %s",
        (
            language &&
            language[0]
        )
            ? language
            : "en-US"
    );

    snprintf(
        csrf_header,
        sizeof(csrf_header),
        "X-CSRFToken: %s",
        csrf_token
    );

    headers =
        curl_slist_append(
            headers,
            "Accept: */*"
        );

    headers =
        curl_slist_append(
            headers,
            lang_header
        );

    headers =
        curl_slist_append(
            headers,
            csrf_header
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-App-ID: 936619743392459"
        );

    headers =
        curl_slist_append(
            headers,
            "X-ASBD-ID: 198387"
        );

    headers =
        curl_slist_append(
            headers,
            "X-Requested-With: XMLHttpRequest"
        );

    headers =
        curl_slist_append(
            headers,
            "Referer: https://www.instagram.com/reels/"
        );

    curl_easy_setopt(
        easy,
        CURLOPT_URL,
        url
    );

    curl_easy_setopt(
        easy,
        CURLOPT_HTTPGET,
        1L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_USERAGENT,
        user_agent
    );

    curl_easy_setopt(
        easy,
        CURLOPT_COOKIE,
        cookie_header
    );

    curl_easy_setopt(
        easy,
        CURLOPT_HTTPHEADER,
        headers
    );

    curl_easy_setopt(
        easy,
        CURLOPT_FOLLOWLOCATION,
        0L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_CONNECTTIMEOUT,
        15L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_TIMEOUT,
        40L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_NOSIGNAL,
        1L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_SSL_VERIFYPEER,
        1L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_SSL_VERIFYHOST,
        2L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_CAINFO,
        ca_path
    );

    curl_easy_setopt(
        easy,
        CURLOPT_ACCEPT_ENCODING,
        ""
    );

    curl_easy_setopt(
        easy,
        CURLOPT_WRITEFUNCTION,
        write_body
    );

    curl_easy_setopt(
        easy,
        CURLOPT_WRITEDATA,
        &g_body
    );

    curl_easy_setopt(
        easy,
        CURLOPT_POST,
        1L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_POSTFIELDS,
        " "
    );

    curl_easy_setopt(
        easy,
        CURLOPT_POSTFIELDSIZE,
        1L
    );

    rc =
        curl_easy_perform(
            easy
        );

    curl_easy_getinfo(
        easy,
        CURLINFO_RESPONSE_CODE,
        &g_status
    );

    curl_easy_getinfo(
        easy,
        CURLINFO_SSL_VERIFYRESULT,
        &g_verify
    );

    if (escaped_cursor) {
        curl_free(
            escaped_cursor
        );
    }

    if (headers) {
        curl_slist_free_all(
            headers
        );
    }

    curl_easy_cleanup(
        easy
    );

    curl_global_cleanup();

    return (int)rc;
}

long magnistra_reels_http_status(void) {
    return g_status;
}

long magnistra_reels_tls_verify_result(void) {
    return g_verify;
}

long long magnistra_reels_body_length(void) {
    return (long long)g_body.size;
}

const unsigned char *magnistra_reels_body(void) {
    return g_body.data;
}
