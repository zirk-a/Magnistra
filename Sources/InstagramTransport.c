#include <syslog.h>
#include "InstagramTransport.h"

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

#define MAGNISTRA_MAX_BODY (12u * 1024u * 1024u)

struct DynamicBody {
    unsigned char *data;
    size_t size;
    size_t capacity;
};

static struct DynamicBody g_body = { NULL, 0, 0 };
static long g_http_status = 0;
static long g_verify_result = -1;
static char g_content_type[512];
static char g_tls_backend[256];
static char g_error[CURL_ERROR_SIZE];

static void reset_state(void) {
    if (g_body.data != NULL) {
        free(g_body.data);
    }

    g_body.data = NULL;
    g_body.size = 0;
    g_body.capacity = 0;

    g_http_status = 0;
    g_verify_result = -1;
    g_content_type[0] = '\0';
    g_tls_backend[0] = '\0';
    g_error[0] = '\0';
}

static int ensure_capacity(
    struct DynamicBody *body,
    size_t needed
) {
    size_t new_capacity;
    unsigned char *new_data;

    if (needed > MAGNISTRA_MAX_BODY) {
        return 0;
    }

    if (needed <= body->capacity) {
        return 1;
    }

    new_capacity =
        body->capacity == 0
            ? 16384
            : body->capacity;

    while (new_capacity < needed) {
        if (
            new_capacity >=
            MAGNISTRA_MAX_BODY / 2
        ) {
            new_capacity =
                MAGNISTRA_MAX_BODY;
            break;
        }

        new_capacity *= 2;
    }

    new_data =
        (unsigned char *)realloc(
            body->data,
            new_capacity
        );

    if (new_data == NULL) {
        return 0;
    }

    body->data = new_data;
    body->capacity = new_capacity;

    return 1;
}

static size_t body_write(
    char *ptr,
    size_t size,
    size_t nmemb,
    void *userdata
) {
    struct DynamicBody *body =
        (struct DynamicBody *)userdata;

    size_t n = size * nmemb;

    if (
        !ensure_capacity(
            body,
            body->size + n + 1
        )
    ) {
        return 0;
    }

    memcpy(
        body->data + body->size,
        ptr,
        n
    );

    body->size += n;
    body->data[body->size] = 0;

    return n;
}

static void capture_tls_backend(void) {
    const curl_version_info_data *vi =
        curl_version_info(
            CURLVERSION_NOW
        );

    if (
        vi != NULL &&
        vi->ssl_version != NULL
    ) {
        snprintf(
            g_tls_backend,
            sizeof(g_tls_backend),
            "%s",
            vi->ssl_version
        );
    } else {
        snprintf(
            g_tls_backend,
            sizeof(g_tls_backend),
            "UNKNOWN"
        );
    }
}

static void capture_common(
    CURL *easy
) {
    char *content_type = NULL;

    curl_easy_getinfo(
        easy,
        CURLINFO_RESPONSE_CODE,
        &g_http_status
    );

    curl_easy_getinfo(
        easy,
        CURLINFO_SSL_VERIFYRESULT,
        &g_verify_result
    );

    curl_easy_getinfo(
        easy,
        CURLINFO_CONTENT_TYPE,
        &content_type
    );

    if (content_type != NULL) {
        snprintf(
            g_content_type,
            sizeof(g_content_type),
            "%s",
            content_type
        );
    }
}

int magnistra_transport_fetch_feed(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *max_id,
    const char *pagination_json
) {
    CURL *easy = NULL;
    CURLcode rc;
    struct curl_slist *headers = NULL;
    char accept_language[512];
    char csrf_header[1024];

    reset_state();

    if (
        ca_path == NULL ||
        ca_path[0] == '\0' ||
        user_agent == NULL ||
        user_agent[0] == '\0' ||
        cookie_header == NULL ||
        cookie_header[0] == '\0' ||
        csrf_token == NULL ||
        csrf_token[0] == '\0'
    ) {
        snprintf(
            g_error,
            sizeof(g_error),
            "invalid feed transport inputs"
        );

        return -1000;
    }

    rc =
        curl_global_init(
            CURL_GLOBAL_DEFAULT
        );

    if (rc != CURLE_OK) {
        snprintf(
            g_error,
            sizeof(g_error),
            "curl_global_init rc=%d",
            (int)rc
        );

        return (int)rc;
    }

    capture_tls_backend();

    easy =
        curl_easy_init();

    if (easy == NULL) {
        snprintf(
            g_error,
            sizeof(g_error),
            "curl_easy_init returned NULL"
        );

        curl_global_cleanup();
        return -1001;
    }

    snprintf(
        accept_language,
        sizeof(accept_language),
        "Accept-Language: %s",
        (
            language != NULL &&
            language[0] != '\0'
        ) ? language : "en-US"
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
            accept_language
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
            "X-Requested-With: XMLHttpRequest"
        );

    headers =
        curl_slist_append(
            headers,
            "Referer: https://www.instagram.com/"
        );

    curl_easy_setopt(
        easy,
        CURLOPT_URL,
        "https://www.instagram.com/api/v1/feed/timeline/"
    );

    if (
        max_id != NULL &&
        max_id[0] != '\0' &&
        pagination_json != NULL &&
        pagination_json[0] != '\0'
    ) {
        headers =
            curl_slist_append(
                headers,
                "Content-Type: application/json"
            );

        curl_easy_setopt(
            easy,
            CURLOPT_POST,
            1L
        );

        curl_easy_setopt(
            easy,
            CURLOPT_POSTFIELDS,
            pagination_json
        );

        curl_easy_setopt(
            easy,
            CURLOPT_POSTFIELDSIZE,
            (long)strlen(
                pagination_json
            )
        );
    } else {
        curl_easy_setopt(
            easy,
            CURLOPT_HTTPGET,
            1L
        );
    }

    curl_easy_setopt(
        easy,
        CURLOPT_USERAGENT,
        user_agent
    );

    curl_easy_setopt(
        easy,
        CURLOPT_FOLLOWLOCATION,
        0L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_CONNECTTIMEOUT,
        12L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_TIMEOUT,
        15L
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
        CURLOPT_WRITEFUNCTION,
        body_write
    );

    curl_easy_setopt(
        easy,
        CURLOPT_WRITEDATA,
        &g_body
    );

    curl_easy_setopt(
        easy,
        CURLOPT_ERRORBUFFER,
        g_error
    );

    rc =
        curl_easy_perform(
            easy
        );
    {
        double _mag34Dns=0.0, _mag34Conn=0.0, _mag34Tls=0.0, _mag34Ttfb=0.0, _mag34Total=0.0;
        long _mag34Status=0;
        (void)curl_easy_getinfo(easy, CURLINFO_NAMELOOKUP_TIME, &_mag34Dns);
        (void)curl_easy_getinfo(easy, CURLINFO_CONNECT_TIME, &_mag34Conn);
        (void)curl_easy_getinfo(easy, CURLINFO_APPCONNECT_TIME, &_mag34Tls);
        (void)curl_easy_getinfo(easy, CURLINFO_STARTTRANSFER_TIME, &_mag34Ttfb);
        (void)curl_easy_getinfo(easy, CURLINFO_TOTAL_TIME, &_mag34Total);
        (void)curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &_mag34Status);
        syslog(LOG_NOTICE, "MAGNISTRA_FEED_TIMING feed=HOME phase=HTTP total_ms=%.1f dns_ms=%.1f tcp_ms=%.1f tls_ms=%.1f first_byte_ms=%.1f status=%ld curl_rc=%d body_bytes=%lu",
            _mag34Total*1000.0, _mag34Dns*1000.0, _mag34Conn*1000.0,
            _mag34Tls*1000.0, _mag34Ttfb*1000.0,
            _mag34Status, (int)rc, (unsigned long)g_body.size);
    }

    capture_common(
        easy
    );

    if (headers != NULL) {
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

int magnistra_transport_fetch_user_info(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *user_id
) {
    CURL *easy = NULL;
    CURLcode rc;
    struct curl_slist *headers = NULL;
    char accept_language[512];
    char csrf_header[1024];
    char profile_url[1024];
    const char *p;

    reset_state();

    if (
        ca_path == NULL ||
        ca_path[0] == '\0' ||
        user_agent == NULL ||
        user_agent[0] == '\0' ||
        cookie_header == NULL ||
        cookie_header[0] == '\0' ||
        csrf_token == NULL ||
        csrf_token[0] == '\0' ||
        user_id == NULL ||
        user_id[0] == '\0'
    ) {
        snprintf(
            g_error,
            sizeof(g_error),
            "invalid profile transport inputs"
        );
        return -3000;
    }

    for (p = user_id; *p != '\0'; ++p) {
        if (*p < '0' || *p > '9') {
            snprintf(
                g_error,
                sizeof(g_error),
                "profile user id is not numeric"
            );
            return -3001;
        }
    }

    snprintf(
        profile_url,
        sizeof(profile_url),
        "https://i.instagram.com/api/v1/users/%s/info/",
        user_id
    );

    rc =
        curl_global_init(
            CURL_GLOBAL_DEFAULT
        );

    if (rc != CURLE_OK) {
        snprintf(
            g_error,
            sizeof(g_error),
            "curl_global_init rc=%d",
            (int)rc
        );
        return (int)rc;
    }

    capture_tls_backend();

    easy = curl_easy_init();

    if (easy == NULL) {
        snprintf(
            g_error,
            sizeof(g_error),
            "curl_easy_init returned NULL"
        );
        curl_global_cleanup();
        return -3002;
    }

    snprintf(
        accept_language,
        sizeof(accept_language),
        "Accept-Language: %s",
        (
            language != NULL &&
            language[0] != '\0'
        ) ? language : "en-US"
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
            accept_language
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
            "X-Requested-With: XMLHttpRequest"
        );

    headers =
        curl_slist_append(
            headers,
            "Referer: https://www.instagram.com/"
        );

    curl_easy_setopt(
        easy,
        CURLOPT_URL,
        profile_url
    );

    curl_easy_setopt(
        easy,
        CURLOPT_USERAGENT,
        user_agent
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
        CURLOPT_WRITEFUNCTION,
        body_write
    );

    curl_easy_setopt(
        easy,
        CURLOPT_WRITEDATA,
        &g_body
    );

    curl_easy_setopt(
        easy,
        CURLOPT_ERRORBUFFER,
        g_error
    );

    rc = curl_easy_perform(easy);

    capture_common(easy);

    if (headers != NULL) {
        curl_slist_free_all(headers);
    }

    curl_easy_cleanup(easy);
    curl_global_cleanup();

    return (int)rc;
}

int magnistra_transport_fetch_comments(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *media_id,
    const char *max_id
) {
    CURL *easy = NULL;
    CURLcode rc;
    struct curl_slist *headers = NULL;
    char accept_language[512];
    char csrf_header[1024];
    char comments_url[4096];
    char *escaped_media = NULL;
    char *escaped_max = NULL;

    reset_state();

    if (
        ca_path == NULL ||
        ca_path[0] == '\0' ||
        user_agent == NULL ||
        user_agent[0] == '\0' ||
        cookie_header == NULL ||
        cookie_header[0] == '\0' ||
        csrf_token == NULL ||
        csrf_token[0] == '\0' ||
        media_id == NULL ||
        media_id[0] == '\0'
    ) {
        snprintf(
            g_error,
            sizeof(g_error),
            "invalid comments transport inputs"
        );
        return -4000;
    }

    rc = curl_global_init(CURL_GLOBAL_DEFAULT);

    if (rc != CURLE_OK) {
        snprintf(
            g_error,
            sizeof(g_error),
            "curl_global_init rc=%d",
            (int)rc
        );
        return (int)rc;
    }

    capture_tls_backend();

    easy = curl_easy_init();

    if (easy == NULL) {
        snprintf(
            g_error,
            sizeof(g_error),
            "curl_easy_init returned NULL"
        );
        curl_global_cleanup();
        return -4001;
    }

    escaped_media =
        curl_easy_escape(
            easy,
            media_id,
            0
        );

    if (escaped_media == NULL) {
        snprintf(
            g_error,
            sizeof(g_error),
            "could not escape media id"
        );
        curl_easy_cleanup(easy);
        curl_global_cleanup();
        return -4002;
    }

    if (
        max_id != NULL &&
        max_id[0] != '\0'
    ) {
        escaped_max =
            curl_easy_escape(
                easy,
                max_id,
                0
            );

        if (escaped_max == NULL) {
            curl_free(escaped_media);
            snprintf(
                g_error,
                sizeof(g_error),
                "could not escape comment cursor"
            );
            curl_easy_cleanup(easy);
            curl_global_cleanup();
            return -4003;
        }

        snprintf(
            comments_url,
            sizeof(comments_url),
            "https://i.instagram.com/api/v1/media/%s/comments/?can_support_threading=true&max_id=%s",
            escaped_media,
            escaped_max
        );
    } else {
        snprintf(
            comments_url,
            sizeof(comments_url),
            "https://i.instagram.com/api/v1/media/%s/comments/?can_support_threading=true",
            escaped_media
        );
    }

    curl_free(escaped_media);

    if (escaped_max != NULL) {
        curl_free(escaped_max);
    }

    snprintf(
        accept_language,
        sizeof(accept_language),
        "Accept-Language: %s",
        (
            language != NULL &&
            language[0] != '\0'
        ) ? language : "en-US"
    );

    snprintf(
        csrf_header,
        sizeof(csrf_header),
        "X-CSRFToken: %s",
        csrf_token
    );

    headers = curl_slist_append(
        headers,
        "Accept: */*"
    );
    headers = curl_slist_append(
        headers,
        accept_language
    );
    headers = curl_slist_append(
        headers,
        csrf_header
    );
    headers = curl_slist_append(
        headers,
        "X-IG-App-ID: 936619743392459"
    );
    headers = curl_slist_append(
        headers,
        "X-Requested-With: XMLHttpRequest"
    );
    headers = curl_slist_append(
        headers,
        "Referer: https://www.instagram.com/"
    );

    curl_easy_setopt(
        easy,
        CURLOPT_URL,
        comments_url
    );
    curl_easy_setopt(
        easy,
        CURLOPT_USERAGENT,
        user_agent
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
        CURLOPT_WRITEFUNCTION,
        body_write
    );
    curl_easy_setopt(
        easy,
        CURLOPT_WRITEDATA,
        &g_body
    );
    curl_easy_setopt(
        easy,
        CURLOPT_ERRORBUFFER,
        g_error
    );

    rc = curl_easy_perform(easy);

    capture_common(easy);

    if (headers != NULL) {
        curl_slist_free_all(headers);
    }

    curl_easy_cleanup(easy);
    curl_global_cleanup();

    return (int)rc;
}

int magnistra_transport_fetch_public_image(
    const char *ca_path,
    const char *user_agent,
    const char *image_url
) {
    CURL *easy = NULL;
    CURLcode rc;

    reset_state();

    if (
        ca_path == NULL ||
        ca_path[0] == '\0' ||
        user_agent == NULL ||
        user_agent[0] == '\0' ||
        image_url == NULL ||
        image_url[0] == '\0'
    ) {
        snprintf(
            g_error,
            sizeof(g_error),
            "invalid image transport inputs"
        );

        return -2000;
    }

    rc =
        curl_global_init(
            CURL_GLOBAL_DEFAULT
        );

    if (rc != CURLE_OK) {
        snprintf(
            g_error,
            sizeof(g_error),
            "curl_global_init rc=%d",
            (int)rc
        );

        return (int)rc;
    }

    capture_tls_backend();

    easy = curl_easy_init();

    if (easy == NULL) {
        snprintf(
            g_error,
            sizeof(g_error),
            "curl_easy_init returned NULL"
        );

        curl_global_cleanup();
        return -2001;
    }

    curl_easy_setopt(
        easy,
        CURLOPT_URL,
        image_url
    );

    curl_easy_setopt(
        easy,
        CURLOPT_USERAGENT,
        user_agent
    );

    curl_easy_setopt(
        easy,
        CURLOPT_FOLLOWLOCATION,
        1L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_MAXREDIRS,
        5L
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
        CURLOPT_WRITEFUNCTION,
        body_write
    );

    curl_easy_setopt(
        easy,
        CURLOPT_WRITEDATA,
        &g_body
    );

    curl_easy_setopt(
        easy,
        CURLOPT_ERRORBUFFER,
        g_error
    );

    rc = curl_easy_perform(easy);

    capture_common(easy);

    curl_easy_cleanup(easy);
    curl_global_cleanup();

    return (int)rc;
}

long magnistra_transport_http_status(void) {
    return g_http_status;
}

long magnistra_transport_tls_verify_result(void) {
    return g_verify_result;
}

long long magnistra_transport_body_length(void) {
    return (long long)g_body.size;
}

const char *magnistra_transport_content_type(void) {
    return g_content_type;
}

const char *magnistra_transport_tls_backend(void) {
    return g_tls_backend;
}

const char *magnistra_transport_error(void) {
    return g_error;
}

const unsigned char *magnistra_transport_body(void) {
    return g_body.data;
}

static unsigned char *g_matrix_login_body = NULL;
static size_t g_matrix_login_body_len = 0;
static long g_matrix_login_http_status = 0;
static long g_matrix_login_tls_verify = -1;

static void magnistra_matrix_login_reset(void)
{
    if (g_matrix_login_body != NULL) {
        free(g_matrix_login_body);
        g_matrix_login_body = NULL;
    }

    g_matrix_login_body_len = 0;
    g_matrix_login_http_status = 0;
    g_matrix_login_tls_verify = -1;
}

static size_t magnistra_matrix_login_write(
    void *contents,
    size_t size,
    size_t nmemb,
    void *userdata
)
{
    size_t incoming = size * nmemb;
    unsigned char *next;

    (void)userdata;

    if (incoming == 0) {
        return 0;
    }

    next = (unsigned char *)realloc(
        g_matrix_login_body,
        g_matrix_login_body_len + incoming + 1
    );

    if (next == NULL) {
        return 0;
    }

    g_matrix_login_body = next;

    memcpy(
        g_matrix_login_body + g_matrix_login_body_len,
        contents,
        incoming
    );

    g_matrix_login_body_len += incoming;
    g_matrix_login_body[g_matrix_login_body_len] = 0;

    return incoming;
}

int magnistra_matrix_login_post_json(
    const char *ca_path,
    const char *url,
    const char *user_agent,
    const char *json_body
)
{
    CURLcode rc;
    CURL *easy = NULL;
    struct curl_slist *headers = NULL;

    magnistra_matrix_login_reset();

    if (
        ca_path == NULL ||
        ca_path[0] == 0 ||
        url == NULL ||
        url[0] == 0 ||
        json_body == NULL
    ) {
        return (int)CURLE_BAD_FUNCTION_ARGUMENT;
    }

    rc = curl_global_init(CURL_GLOBAL_DEFAULT);
    if (rc != CURLE_OK) {
        return (int)rc;
    }

    easy = curl_easy_init();
    if (easy == NULL) {
        curl_global_cleanup();
        return (int)CURLE_FAILED_INIT;
    }

    headers = curl_slist_append(headers, "Content-Type: application/json");
    headers = curl_slist_append(headers, "Accept: application/json");

    curl_easy_setopt(easy, CURLOPT_URL, url);
    curl_easy_setopt(easy, CURLOPT_POST, 1L);
    curl_easy_setopt(easy, CURLOPT_POSTFIELDS, json_body);
    curl_easy_setopt(easy, CURLOPT_POSTFIELDSIZE, (long)strlen(json_body));
    curl_easy_setopt(easy, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(easy, CURLOPT_MAXREDIRS, 3L);
    curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT, 20L);
    curl_easy_setopt(easy, CURLOPT_TIMEOUT, 40L);
    curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(easy, CURLOPT_CAINFO, ca_path);

    if (user_agent != NULL && user_agent[0] != 0) {
        curl_easy_setopt(easy, CURLOPT_USERAGENT, user_agent);
    }

    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, magnistra_matrix_login_write);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, NULL);

    rc = curl_easy_perform(easy);

    curl_easy_getinfo(
        easy,
        CURLINFO_RESPONSE_CODE,
        &g_matrix_login_http_status
    );

    curl_easy_getinfo(
        easy,
        CURLINFO_SSL_VERIFYRESULT,
        &g_matrix_login_tls_verify
    );

    if (headers != NULL) {
        curl_slist_free_all(headers);
    }

    curl_easy_cleanup(easy);
    curl_global_cleanup();

    return (int)rc;
}

long magnistra_matrix_login_http_status(void)
{
    return g_matrix_login_http_status;
}

long magnistra_matrix_login_tls_verify_result(void)
{
    return g_matrix_login_tls_verify;
}

long long magnistra_matrix_login_body_length(void)
{
    return (long long)g_matrix_login_body_len;
}

const unsigned char *magnistra_matrix_login_body(void)
{
    return g_matrix_login_body;
}

static unsigned char *g_matrix_space_body = NULL;
static size_t g_matrix_space_body_len = 0;
static long g_matrix_space_http_status = 0;
static long g_matrix_space_tls_verify = -1;

static void magnistra_matrix_space_reset(void)
{
    if (g_matrix_space_body != NULL) {
        free(g_matrix_space_body);
        g_matrix_space_body = NULL;
    }

    g_matrix_space_body_len = 0;
    g_matrix_space_http_status = 0;
    g_matrix_space_tls_verify = -1;
}

static size_t magnistra_matrix_space_write(
    void *contents,
    size_t size,
    size_t nmemb,
    void *userdata
)
{
    size_t incoming = size * nmemb;
    unsigned char *next;

    (void)userdata;

    if (incoming == 0) {
        return 0;
    }

    next = (unsigned char *)realloc(
        g_matrix_space_body,
        g_matrix_space_body_len + incoming + 1
    );

    if (next == NULL) {
        return 0;
    }

    g_matrix_space_body = next;

    memcpy(
        g_matrix_space_body + g_matrix_space_body_len,
        contents,
        incoming
    );

    g_matrix_space_body_len += incoming;
    g_matrix_space_body[g_matrix_space_body_len] = 0;

    return incoming;
}

int magnistra_matrix_space_get_json(
    const char *ca_path,
    const char *url,
    const char *access_token,
    const char *user_agent
)
{
    CURLcode rc;
    CURL *easy = NULL;
    struct curl_slist *headers = NULL;
    char *authorization = NULL;

    magnistra_matrix_space_reset();

    if (
        ca_path == NULL ||
        ca_path[0] == 0 ||
        url == NULL ||
        url[0] == 0 ||
        access_token == NULL ||
        access_token[0] == 0
    ) {
        return (int)CURLE_BAD_FUNCTION_ARGUMENT;
    }

    rc = curl_global_init(CURL_GLOBAL_DEFAULT);
    if (rc != CURLE_OK) {
        return (int)rc;
    }

    easy = curl_easy_init();

    if (easy == NULL) {
        curl_global_cleanup();
        return (int)CURLE_FAILED_INIT;
    }

    headers =
        curl_slist_append(
            headers,
            "Accept: application/json"
        );

    {
        size_t needed =
            strlen("Authorization: Bearer ") +
            strlen(access_token) +
            1;

        authorization =
            (char *)malloc(needed);

        if (authorization == NULL) {
            curl_slist_free_all(headers);
            curl_easy_cleanup(easy);
            curl_global_cleanup();
            return (int)CURLE_OUT_OF_MEMORY;
        }

        snprintf(
            authorization,
            needed,
            "Authorization: Bearer %s",
            access_token
        );

        headers =
            curl_slist_append(
                headers,
                authorization
            );

        free(authorization);
        authorization = NULL;
    }

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
        CURLOPT_HTTPHEADER,
        headers
    );

    curl_easy_setopt(
        easy,
        CURLOPT_FOLLOWLOCATION,
        1L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_MAXREDIRS,
        3L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_CONNECTTIMEOUT,
        20L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_TIMEOUT,
        60L
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

    if (user_agent != NULL && user_agent[0] != 0) {
        curl_easy_setopt(
            easy,
            CURLOPT_USERAGENT,
            user_agent
        );
    }

    curl_easy_setopt(
        easy,
        CURLOPT_WRITEFUNCTION,
        magnistra_matrix_space_write
    );

    curl_easy_setopt(
        easy,
        CURLOPT_WRITEDATA,
        NULL
    );

    rc =
        curl_easy_perform(
            easy
        );

    curl_easy_getinfo(
        easy,
        CURLINFO_RESPONSE_CODE,
        &g_matrix_space_http_status
    );

    curl_easy_getinfo(
        easy,
        CURLINFO_SSL_VERIFYRESULT,
        &g_matrix_space_tls_verify
    );

    if (headers != NULL) {
        curl_slist_free_all(headers);
    }

    curl_easy_cleanup(easy);
    curl_global_cleanup();

    return (int)rc;
}

long magnistra_matrix_space_http_status(void)
{
    return g_matrix_space_http_status;
}

long magnistra_matrix_space_tls_verify_result(void)
{
    return g_matrix_space_tls_verify;
}

long long magnistra_matrix_space_body_length(void)
{
    return (long long)g_matrix_space_body_len;
}

const unsigned char *magnistra_matrix_space_body(void)
{
    return g_matrix_space_body;
}

int magnistra_transport_post_action_request(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *relative_path,
    const char *post_body,
    int use_post
) {
    CURL *easy = NULL;
    CURLcode rc;
    struct curl_slist *headers = NULL;
    char url[4096];
    char language_header[512];
    char csrf_header[1024];

    reset_state();

    if (
        ca_path == NULL ||
        ca_path[0] == '\0' ||
        user_agent == NULL ||
        user_agent[0] == '\0' ||
        cookie_header == NULL ||
        cookie_header[0] == '\0' ||
        csrf_token == NULL ||
        csrf_token[0] == '\0' ||
        relative_path == NULL ||
        relative_path[0] == '\0'
    ) {
        return -9300;
    }

    snprintf(
        url,
        sizeof(url),
        "https://i.instagram.com/api/v1/%s",
        relative_path
    );

    snprintf(
        language_header,
        sizeof(language_header),
        "Accept-Language: %s",
        (
            language != NULL &&
            language[0] != '\0'
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

    rc = curl_global_init(CURL_GLOBAL_DEFAULT);

    if (rc != CURLE_OK) {
        return (int)rc;
    }

    easy = curl_easy_init();

    if (easy == NULL) {
        curl_global_cleanup();
        return -9301;
    }

    headers = curl_slist_append(headers, "Accept: */*");
    headers = curl_slist_append(headers, language_header);
    headers = curl_slist_append(headers, csrf_header);
    headers = curl_slist_append(
        headers,
        "X-IG-App-ID: 567067343352427"
    );
    headers = curl_slist_append(
        headers,
        "X-Requested-With: XMLHttpRequest"
    );
    headers = curl_slist_append(
        headers,
        "Origin: https://www.instagram.com"
    );
    headers = curl_slist_append(
        headers,
        "Referer: https://www.instagram.com/"
    );

    if (use_post) {
        headers = curl_slist_append(
            headers,
            "Content-Type: application/x-www-form-urlencoded"
        );
    }

    curl_easy_setopt(easy, CURLOPT_URL, url);
    curl_easy_setopt(easy, CURLOPT_USERAGENT, user_agent);
    curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT, 15L);
    curl_easy_setopt(easy, CURLOPT_TIMEOUT, 40L);
    curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(easy, CURLOPT_CAINFO, ca_path);
    curl_easy_setopt(easy, CURLOPT_COOKIE, cookie_header);
    curl_easy_setopt(easy, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, body_write);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, &g_body);
    curl_easy_setopt(easy, CURLOPT_ERRORBUFFER, g_error);

    if (use_post) {
        const char *body =
            (
                post_body != NULL
            )
                ? post_body
                : "";

        curl_easy_setopt(easy, CURLOPT_POST, 1L);
        curl_easy_setopt(easy, CURLOPT_POSTFIELDS, body);
        curl_easy_setopt(
            easy,
            CURLOPT_POSTFIELDSIZE,
            (long)strlen(body)
        );
    }

    rc = curl_easy_perform(easy);

    capture_common(easy);

    curl_slist_free_all(headers);
    curl_easy_cleanup(easy);
    curl_global_cleanup();

    return (int)rc;
}
