#include <syslog.h>
#include "ExploreTransport.h"

#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static CURL *g_magnistra_explore_keepalive_easy = NULL;

int magnistra_explore_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *max_id
) {
    CURL *easy = NULL;
    int magnistra_explore_keep_after_request = 0;
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

    easy = g_magnistra_explore_keepalive_easy;
    if (easy) {
        curl_easy_reset(easy);
    } else {
        easy = curl_easy_init();
        g_magnistra_explore_keepalive_easy = easy;
    }

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
            "https://www.instagram.com/api/v1/discover/web/explore_grid/?max_id=%s",
            escaped_cursor
        );
    } else {
        snprintf(
            url,
            sizeof(url),
            "https://www.instagram.com/api/v1/discover/web/explore_grid/"
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
            "Referer: https://www.instagram.com/explore/"
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

    rc = curl_easy_perform(easy);
    {
        double _mag34Dns=0.0, _mag34Conn=0.0, _mag34Tls=0.0, _mag34Ttfb=0.0, _mag34Total=0.0;
        long _mag34Status=0;
        (void)curl_easy_getinfo(easy, CURLINFO_NAMELOOKUP_TIME, &_mag34Dns);
        (void)curl_easy_getinfo(easy, CURLINFO_CONNECT_TIME, &_mag34Conn);
        (void)curl_easy_getinfo(easy, CURLINFO_APPCONNECT_TIME, &_mag34Tls);
        (void)curl_easy_getinfo(easy, CURLINFO_STARTTRANSFER_TIME, &_mag34Ttfb);
        (void)curl_easy_getinfo(easy, CURLINFO_TOTAL_TIME, &_mag34Total);
        (void)curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &_mag34Status);
        syslog(LOG_NOTICE, "MAGNISTRA_FEED_TIMING feed=EXPLORE phase=HTTP total_ms=%.1f dns_ms=%.1f tcp_ms=%.1f tls_ms=%.1f first_byte_ms=%.1f status=%ld curl_rc=%d body_bytes=%lu",
            _mag34Total*1000.0, _mag34Dns*1000.0, _mag34Conn*1000.0,
            _mag34Tls*1000.0, _mag34Ttfb*1000.0,
            _mag34Status, (int)rc, (unsigned long)g_body.size);
    }

    magnistra_explore_keep_after_request = (rc == CURLE_OK);

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

    if (!magnistra_explore_keep_after_request) {
        curl_easy_cleanup(easy);
        g_magnistra_explore_keepalive_easy = NULL;
    }

    curl_global_cleanup();

    return (int)rc;
}

static MagnistraExploreBuffer g_search_body = {
    NULL,
    0,
    0
};

static long g_search_status = 0;
static long g_search_verify = -1;

static void magnistra_explore_search_reset(void) {
    if (g_search_body.data) {
        free(g_search_body.data);
    }

    g_search_body.data = NULL;
    g_search_body.size = 0;
    g_search_body.capacity = 0;
    g_search_status = 0;
    g_search_verify = -1;
}

static size_t magnistra_explore_search_write(
    char *ptr,
    size_t size,
    size_t nmemb,
    void *userdata
) {
    MagnistraExploreBuffer *buffer =
        (MagnistraExploreBuffer *)userdata;
    size_t incoming = size * nmemb;
    size_t wanted;
    size_t next;
    unsigned char *grown;

    if (!incoming) {
        return 0;
    }

    wanted = buffer->size + incoming + 1;

    if (wanted > buffer->capacity) {
        next = buffer->capacity
            ? buffer->capacity
            : 4096;

        while (next < wanted) {
            next *= 2;
        }

        grown =
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

static int magnistra_explore_search_copy_between(
    const char *source,
    const char *prefix,
    const char *suffix,
    char *output,
    size_t output_size
) {
    const char *start;
    const char *end;
    size_t length;

    if (
        source == NULL ||
        prefix == NULL ||
        suffix == NULL ||
        output == NULL ||
        output_size < 2
    ) {
        return 0;
    }

    start = strstr(source, prefix);

    if (start == NULL) {
        return 0;
    }

    start += strlen(prefix);
    end = strstr(start, suffix);

    if (end == NULL || end <= start) {
        return 0;
    }

    length = (size_t)(end - start);

    if (length >= output_size) {
        return 0;
    }

    memcpy(output, start, length);
    output[length] = 0;

    return 1;
}

static int magnistra_explore_search_extract_fb_dtsg(
    const char *html,
    char *output,
    size_t output_size
) {
    static const char *prefixes[] = {
        "[\"DTSGInitialData\",[],{\"token\":\"",
        "name=\"fb_dtsg\" value=\"",
        "name='fb_dtsg' value='"
    };
    static const char *suffixes[] = {
        "\"",
        "\"",
        "'"
    };
    size_t i;

    for (
        i = 0;
        i < sizeof(prefixes) / sizeof(prefixes[0]);
        i++
    ) {
        if (
            magnistra_explore_search_copy_between(
                html,
                prefixes[i],
                suffixes[i],
                output,
                output_size
            )
        ) {
            return 1;
        }
    }

    return 0;
}

static int magnistra_explore_search_extract_jazoest(
    const char *html,
    char *output,
    size_t output_size
) {
    if (
        magnistra_explore_search_copy_between(
            html,
            "name=\"jazoest\" value=\"",
            "\"",
            output,
            output_size
        )
    ) {
        return 1;
    }

    if (
        magnistra_explore_search_copy_between(
            html,
            "name='jazoest' value='",
            "'",
            output,
            output_size
        )
    ) {
        return 1;
    }

    return 0;
}

static int magnistra_explore_search_derive_jazoest(
    const char *fb_dtsg,
    char *output,
    size_t output_size
) {
    size_t i;
    size_t used = 0;
    int written;

    if (
        fb_dtsg == NULL ||
        fb_dtsg[0] == 0 ||
        output == NULL ||
        output_size < 4
    ) {
        return 0;
    }

    output[0] = '2';
    output[1] = 0;
    used = 1;

    for (i = 0; fb_dtsg[i] != 0; i++) {
        written =
            snprintf(
                output + used,
                output_size - used,
                "%u",
                (unsigned int)
                    (unsigned char)fb_dtsg[i]
            );

        if (
            written <= 0 ||
            (size_t)written >=
                output_size - used
        ) {
            return 0;
        }

        used += (size_t)written;
    }

    return 1;
}

static struct curl_slist *magnistra_explore_search_headers(
    const char *language,
    const char *csrf_token,
    const char *friendly_name
) {
    struct curl_slist *headers = NULL;
    char line[2048];

    headers = curl_slist_append(
        headers,
        "Accept: */*"
    );
    headers = curl_slist_append(
        headers,
        "Referer: https://www.instagram.com/"
    );
    headers = curl_slist_append(
        headers,
        "X-IG-App-ID: 936619743392459"
    );
    headers = curl_slist_append(
        headers,
        "X-ASBD-ID: 198387"
    );
    headers = curl_slist_append(
        headers,
        "X-Requested-With: XMLHttpRequest"
    );
    headers = curl_slist_append(
        headers,
        "Sec-Fetch-Site: same-origin"
    );
    headers = curl_slist_append(
        headers,
        "Sec-Fetch-Mode: cors"
    );
    headers = curl_slist_append(
        headers,
        "Sec-Fetch-Dest: empty"
    );

    if (language != NULL && language[0] != 0) {
        snprintf(
            line,
            sizeof(line),
            "Accept-Language: %s",
            language
        );
        headers = curl_slist_append(
            headers,
            line
        );
    }

    if (csrf_token != NULL && csrf_token[0] != 0) {
        snprintf(
            line,
            sizeof(line),
            "X-CSRFToken: %s",
            csrf_token
        );
        headers = curl_slist_append(
            headers,
            line
        );
    }

    if (friendly_name != NULL && friendly_name[0] != 0) {
        snprintf(
            line,
            sizeof(line),
            "X-FB-Friendly-Name: %s",
            friendly_name
        );
        headers = curl_slist_append(
            headers,
            line
        );
    }

    return headers;
}

static CURLcode magnistra_explore_search_get_root(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token
) {
    CURL *curl = NULL;
    CURLcode code = CURLE_FAILED_INIT;
    struct curl_slist *headers = NULL;

    magnistra_explore_search_reset();

    curl = curl_easy_init();

    if (curl == NULL) {
        return CURLE_FAILED_INIT;
    }

    headers =
        magnistra_explore_search_headers(
            language,
            csrf_token,
            NULL
        );

    curl_easy_setopt(
        curl,
        CURLOPT_URL,
        "https://www.instagram.com/"
    );
    curl_easy_setopt(
        curl,
        CURLOPT_HTTPHEADER,
        headers
    );
    curl_easy_setopt(
        curl,
        CURLOPT_FOLLOWLOCATION,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_MAXREDIRS,
        5L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_CONNECTTIMEOUT,
        20L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_TIMEOUT,
        45L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_NOSIGNAL,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_SSL_VERIFYPEER,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_SSL_VERIFYHOST,
        2L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_CAINFO,
        ca_path
    );
    curl_easy_setopt(
        curl,
        CURLOPT_ACCEPT_ENCODING,
        ""
    );
    curl_easy_setopt(
        curl,
        CURLOPT_WRITEFUNCTION,
        magnistra_explore_search_write
    );
    curl_easy_setopt(
        curl,
        CURLOPT_WRITEDATA,
        &g_search_body
    );

    if (user_agent != NULL && user_agent[0] != 0) {
        curl_easy_setopt(
            curl,
            CURLOPT_USERAGENT,
            user_agent
        );
    }

    if (cookies != NULL && cookies[0] != 0) {
        curl_easy_setopt(
            curl,
            CURLOPT_COOKIE,
            cookies
        );
    }

    code = curl_easy_perform(curl);

    curl_easy_getinfo(
        curl,
        CURLINFO_RESPONSE_CODE,
        &g_search_status
    );
    curl_easy_getinfo(
        curl,
        CURLINFO_SSL_VERIFYRESULT,
        &g_search_verify
    );

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return code;
}

static CURLcode magnistra_explore_search_post_graphql(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *fb_dtsg,
    const char *jazoest,
    const char *variables_json,
    const char *doc_id,
    const char *friendly_name
) {
    CURL *curl = NULL;
    CURLcode code = CURLE_FAILED_INIT;
    struct curl_slist *headers = NULL;
    char *escaped_dtsg = NULL;
    char *escaped_jazoest = NULL;
    char *escaped_variables = NULL;
    char *escaped_doc_id = NULL;
    char *escaped_friendly = NULL;
    char *post_fields = NULL;
    size_t post_size;

    magnistra_explore_search_reset();

    curl = curl_easy_init();

    if (curl == NULL) {
        return CURLE_FAILED_INIT;
    }

    headers =
        magnistra_explore_search_headers(
            language,
            csrf_token,
            friendly_name
        );

    headers = curl_slist_append(
        headers,
        "Content-Type: application/x-www-form-urlencoded"
    );
    headers = curl_slist_append(
        headers,
        "Origin: https://www.instagram.com"
    );
    headers = curl_slist_append(
        headers,
        "Referer: https://www.instagram.com/your_activity/interactions/likes/"
    );

    escaped_dtsg =
        curl_easy_escape(curl, fb_dtsg, 0);
    escaped_jazoest =
        curl_easy_escape(curl, jazoest, 0);
    escaped_variables =
        curl_easy_escape(curl, variables_json, 0);
    escaped_doc_id =
        curl_easy_escape(curl, doc_id, 0);
    escaped_friendly =
        curl_easy_escape(curl, friendly_name, 0);

    if (
        escaped_dtsg == NULL ||
        escaped_jazoest == NULL ||
        escaped_variables == NULL ||
        escaped_doc_id == NULL ||
        escaped_friendly == NULL
    ) {
        if (escaped_dtsg) curl_free(escaped_dtsg);
        if (escaped_jazoest) curl_free(escaped_jazoest);
        if (escaped_variables) curl_free(escaped_variables);
        if (escaped_doc_id) curl_free(escaped_doc_id);
        if (escaped_friendly) curl_free(escaped_friendly);
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        return CURLE_OUT_OF_MEMORY;
    }

    post_size =
        strlen(escaped_dtsg) +
        strlen(escaped_jazoest) +
        strlen(escaped_variables) +
        strlen(escaped_doc_id) +
        strlen(escaped_friendly) +
        256;

    post_fields =
        (char *)malloc(post_size);

    if (post_fields == NULL) {
        curl_free(escaped_dtsg);
        curl_free(escaped_jazoest);
        curl_free(escaped_variables);
        curl_free(escaped_doc_id);
        curl_free(escaped_friendly);
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        return CURLE_OUT_OF_MEMORY;
    }

    snprintf(
        post_fields,
        post_size,
        "fb_dtsg=%s"
        "&jazoest=%s"
        "&variables=%s"
        "&doc_id=%s"
        "&fb_api_caller_class=RelayModern"
        "&fb_api_req_friendly_name=%s"
        "&server_timestamps=true",
        escaped_dtsg,
        escaped_jazoest,
        escaped_variables,
        escaped_doc_id,
        escaped_friendly
    );

    curl_easy_setopt(
        curl,
        CURLOPT_URL,
        "https://www.instagram.com/api/graphql"
    );
    curl_easy_setopt(
        curl,
        CURLOPT_HTTPHEADER,
        headers
    );
    curl_easy_setopt(
        curl,
        CURLOPT_POST,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_POSTFIELDS,
        post_fields
    );
    curl_easy_setopt(
        curl,
        CURLOPT_POSTFIELDSIZE,
        (long)strlen(post_fields)
    );
    curl_easy_setopt(
        curl,
        CURLOPT_FOLLOWLOCATION,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_MAXREDIRS,
        5L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_CONNECTTIMEOUT,
        20L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_TIMEOUT,
        45L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_NOSIGNAL,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_SSL_VERIFYPEER,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_SSL_VERIFYHOST,
        2L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_CAINFO,
        ca_path
    );
    curl_easy_setopt(
        curl,
        CURLOPT_ACCEPT_ENCODING,
        ""
    );
    curl_easy_setopt(
        curl,
        CURLOPT_WRITEFUNCTION,
        magnistra_explore_search_write
    );
    curl_easy_setopt(
        curl,
        CURLOPT_WRITEDATA,
        &g_search_body
    );

    if (user_agent != NULL && user_agent[0] != 0) {
        curl_easy_setopt(
            curl,
            CURLOPT_USERAGENT,
            user_agent
        );
    }

    if (cookies != NULL && cookies[0] != 0) {
        curl_easy_setopt(
            curl,
            CURLOPT_COOKIE,
            cookies
        );
    }

    code = curl_easy_perform(curl);

    curl_easy_getinfo(
        curl,
        CURLINFO_RESPONSE_CODE,
        &g_search_status
    );
    curl_easy_getinfo(
        curl,
        CURLINFO_SSL_VERIFYRESULT,
        &g_search_verify
    );

    free(post_fields);
    curl_free(escaped_dtsg);
    curl_free(escaped_jazoest);
    curl_free(escaped_variables);
    curl_free(escaped_doc_id);
    curl_free(escaped_friendly);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return code;
}

static int magnistra_explore_search_body_looks_json(void) {
    size_t i;

    if (
        g_search_body.data == NULL ||
        g_search_body.size == 0
    ) {
        return 0;
    }

    for (i = 0; i < g_search_body.size; i++) {
        unsigned char ch = g_search_body.data[i];

        if (
            ch == ' ' ||
            ch == '\t' ||
            ch == '\r' ||
            ch == '\n'
        ) {
            continue;
        }

        return ch == '{' || ch == '[';
    }

    return 0;
}

int magnistra_explore_graphql_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *variables_json,
    const char *doc_id,
    const char *friendly_name
) {
    CURLcode code;
    char fb_dtsg[1024];
    char jazoest[2048];
    int jazoest_ok = 0;

    if (
        ca_path == NULL ||
        ca_path[0] == 0 ||
        user_agent == NULL ||
        user_agent[0] == 0 ||
        cookies == NULL ||
        cookies[0] == 0 ||
        csrf_token == NULL ||
        csrf_token[0] == 0 ||
        variables_json == NULL ||
        variables_json[0] == 0 ||
        doc_id == NULL ||
        doc_id[0] == 0 ||
        friendly_name == NULL ||
        friendly_name[0] == 0
    ) {
        return -6800;
    }

    fb_dtsg[0] = 0;
    jazoest[0] = 0;

    code = curl_global_init(CURL_GLOBAL_DEFAULT);

    if (code != CURLE_OK) {
        return (int)code;
    }

    code =
        magnistra_explore_search_get_root(
            ca_path,
            user_agent,
            language,
            cookies,
            csrf_token
        );

    if (
        code != CURLE_OK ||
        g_search_status < 200 ||
        g_search_status >= 300 ||
        g_search_body.data == NULL ||
        g_search_body.size == 0
    ) {
        curl_global_cleanup();
        return (int)code;
    }

    if (
        !magnistra_explore_search_extract_fb_dtsg(
            (const char *)g_search_body.data,
            fb_dtsg,
            sizeof(fb_dtsg)
        )
    ) {
        g_search_status = 468;
        curl_global_cleanup();
        return (int)CURLE_GOT_NOTHING;
    }

    jazoest_ok =
        magnistra_explore_search_extract_jazoest(
            (const char *)g_search_body.data,
            jazoest,
            sizeof(jazoest)
        );

    if (!jazoest_ok) {
        jazoest_ok =
            magnistra_explore_search_derive_jazoest(
                fb_dtsg,
                jazoest,
                sizeof(jazoest)
            );
    }

    if (!jazoest_ok) {
        g_search_status = 469;
        curl_global_cleanup();
        return (int)CURLE_GOT_NOTHING;
    }

    code =
        magnistra_explore_search_post_graphql(
            ca_path,
            user_agent,
            language,
            cookies,
            csrf_token,
            fb_dtsg,
            jazoest,
            variables_json,
            doc_id,
            friendly_name
        );

    memset(fb_dtsg, 0, sizeof(fb_dtsg));
    memset(jazoest, 0, sizeof(jazoest));

    curl_global_cleanup();

    if (
        code == CURLE_OK &&
        g_search_status >= 200 &&
        g_search_status < 300 &&
        g_search_verify == 0 &&
        magnistra_explore_search_body_looks_json()
    ) {
        return 0;
    }

    return (int)code;
}

static int magnistra_explore_wbloks_extract_lsd(
    const char *html,
    char *output,
    size_t output_size
) {
    static const char *prefixes[] = {
        "[\"LSD\",[],{\"token\":\"",
        "\"LSD\",[],{\"token\":\"",
        "name=\"lsd\" value=\"",
        "\"lsd\":\""
    };
    static const char *suffixes[] = {
        "\"",
        "\"",
        "\"",
        "\""
    };
    size_t i;

    for (
        i = 0;
        i < sizeof(prefixes) / sizeof(prefixes[0]);
        i++
    ) {
        if (
            magnistra_explore_search_copy_between(
                html,
                prefixes[i],
                suffixes[i],
                output,
                output_size
            )
        ) {
            return 1;
        }
    }

    return 0;
}

static int magnistra_explore_wbloks_extract_bkv(
    const char *html,
    char *output,
    size_t output_size
) {
    static const char *prefixes[] = {
        "\"__bkv\":\"",
        "__bkv=",
        "__bkv%3D"
    };
    static const char *suffixes[] = {
        "\"",
        "&",
        "&"
    };
    size_t i;

    for (
        i = 0;
        i < sizeof(prefixes) / sizeof(prefixes[0]);
        i++
    ) {
        if (
            magnistra_explore_search_copy_between(
                html,
                prefixes[i],
                suffixes[i],
                output,
                output_size
            )
        ) {
            return 1;
        }
    }

    return 0;
}

static char g_magnistra_wbloks_hs[2048];
static char g_magnistra_wbloks_hsi[2048];
static char g_magnistra_wbloks_s[2048];
static char g_magnistra_wbloks_dyn[16384];
static char g_magnistra_wbloks_csr[16384];
static char g_magnistra_wbloks_rev[128];
static char g_magnistra_wbloks_spin_t[128];

static void magnistra_wbloks_dynamic_reset(void) {
    g_magnistra_wbloks_hs[0] = 0;
    g_magnistra_wbloks_hsi[0] = 0;
    g_magnistra_wbloks_s[0] = 0;
    g_magnistra_wbloks_dyn[0] = 0;
    g_magnistra_wbloks_csr[0] = 0;
    g_magnistra_wbloks_rev[0] = 0;
    g_magnistra_wbloks_spin_t[0] = 0;
}

static void magnistra_wbloks_dynamic_extract(
    const char *html
) {
    magnistra_wbloks_dynamic_reset();

    if (html == NULL) {
        return;
    }

    (void)magnistra_explore_search_copy_between(
        html,
        "\"__hs\":\"",
        "\"",
        g_magnistra_wbloks_hs,
        sizeof(g_magnistra_wbloks_hs)
    );

    if (g_magnistra_wbloks_hs[0] == 0) {
        (void)magnistra_explore_search_copy_between(
            html,
            "\"hs\":\"",
            "\"",
            g_magnistra_wbloks_hs,
            sizeof(g_magnistra_wbloks_hs)
        );
    }

    (void)magnistra_explore_search_copy_between(
        html,
        "\"__hsi\":\"",
        "\"",
        g_magnistra_wbloks_hsi,
        sizeof(g_magnistra_wbloks_hsi)
    );

    if (g_magnistra_wbloks_hsi[0] == 0) {
        (void)magnistra_explore_search_copy_between(
            html,
            "\"hsi\":\"",
            "\"",
            g_magnistra_wbloks_hsi,
            sizeof(g_magnistra_wbloks_hsi)
        );
    }

    (void)magnistra_explore_search_copy_between(
        html,
        "\"__s\":\"",
        "\"",
        g_magnistra_wbloks_s,
        sizeof(g_magnistra_wbloks_s)
    );

    (void)magnistra_explore_search_copy_between(
        html,
        "\"__dyn\":\"",
        "\"",
        g_magnistra_wbloks_dyn,
        sizeof(g_magnistra_wbloks_dyn)
    );

    (void)magnistra_explore_search_copy_between(
        html,
        "\"__csr\":\"",
        "\"",
        g_magnistra_wbloks_csr,
        sizeof(g_magnistra_wbloks_csr)
    );

    (void)magnistra_explore_search_copy_between(
        html,
        "\"client_revision\":",
        ",",
        g_magnistra_wbloks_rev,
        sizeof(g_magnistra_wbloks_rev)
    );

    if (g_magnistra_wbloks_rev[0] == 0) {
        (void)magnistra_explore_search_copy_between(
            html,
            "\"__rev\":",
            ",",
            g_magnistra_wbloks_rev,
            sizeof(g_magnistra_wbloks_rev)
        );
    }

    (void)magnistra_explore_search_copy_between(
        html,
        "\"spin_t\":",
        ",",
        g_magnistra_wbloks_spin_t,
        sizeof(g_magnistra_wbloks_spin_t)
    );

    if (g_magnistra_wbloks_spin_t[0] == 0) {
        (void)magnistra_explore_search_copy_between(
            html,
            "\"__spin_t\":",
            ",",
            g_magnistra_wbloks_spin_t,
            sizeof(g_magnistra_wbloks_spin_t)
        );
    }
}

static CURLcode magnistra_explore_wbloks_post(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *fb_dtsg,
    const char *jazoest,
    const char *lsd,
    const char *bkv,
    const char *app_id,
    const char *request_type,
    const char *params_json
) {
    CURL *curl = NULL;
    CURLcode code = CURLE_FAILED_INIT;
    struct curl_slist *headers = NULL;
    char *escaped_dtsg = NULL;
    char *escaped_jazoest = NULL;
    char *escaped_lsd = NULL;
    char *escaped_params = NULL;
    char *escaped_app_id = NULL;
    char *escaped_type = NULL;
    char *escaped_bkv = NULL;
    char *escaped_hs = NULL;
    char *escaped_hsi = NULL;
    char *escaped_s = NULL;
    char *escaped_dyn = NULL;
    char *escaped_csr = NULL;
    char *escaped_rev = NULL;
    char *escaped_spin_t = NULL;
    char url[8192];
    char *post_fields = NULL;
    size_t post_size;

    magnistra_explore_search_reset();

    curl = curl_easy_init();

    if (curl == NULL) {
        return CURLE_FAILED_INIT;
    }

    headers =
        magnistra_explore_search_headers(
            language,
            csrf_token,
            NULL
        );

    headers = curl_slist_append(
        headers,
        "Content-Type: application/x-www-form-urlencoded;charset=UTF-8"
    );
    headers = curl_slist_append(
        headers,
        "Origin: https://www.instagram.com"
    );

    escaped_dtsg =
        curl_easy_escape(curl, fb_dtsg, 0);
    escaped_jazoest =
        curl_easy_escape(curl, jazoest, 0);
    escaped_lsd =
        curl_easy_escape(curl, lsd, 0);
    escaped_params =
        curl_easy_escape(curl, params_json, 0);
    escaped_app_id =
        curl_easy_escape(curl, app_id, 0);
    escaped_type =
        curl_easy_escape(curl, request_type, 0);

    escaped_hs =
        curl_easy_escape(curl, g_magnistra_wbloks_hs, 0);
    escaped_hsi =
        curl_easy_escape(curl, g_magnistra_wbloks_hsi, 0);
    escaped_s =
        curl_easy_escape(curl, g_magnistra_wbloks_s, 0);
    escaped_dyn =
        curl_easy_escape(curl, g_magnistra_wbloks_dyn, 0);
    escaped_csr =
        curl_easy_escape(curl, g_magnistra_wbloks_csr, 0);
    escaped_rev =
        curl_easy_escape(curl, g_magnistra_wbloks_rev, 0);
    escaped_spin_t =
        curl_easy_escape(curl, g_magnistra_wbloks_spin_t, 0);

    if (bkv != NULL && bkv[0] != 0) {
        escaped_bkv =
            curl_easy_escape(curl, bkv, 0);
    }

    if (
        escaped_dtsg == NULL ||
        escaped_jazoest == NULL ||
        escaped_lsd == NULL ||
        escaped_params == NULL ||
        escaped_app_id == NULL ||
        escaped_type == NULL ||
        escaped_hs == NULL ||
        escaped_hsi == NULL ||
        escaped_s == NULL ||
        escaped_dyn == NULL ||
        escaped_csr == NULL ||
        escaped_rev == NULL ||
        escaped_spin_t == NULL
    ) {
        if (escaped_dtsg) curl_free(escaped_dtsg);
        if (escaped_jazoest) curl_free(escaped_jazoest);
        if (escaped_lsd) curl_free(escaped_lsd);
        if (escaped_params) curl_free(escaped_params);
        if (escaped_app_id) curl_free(escaped_app_id);
        if (escaped_type) curl_free(escaped_type);
        if (escaped_bkv) curl_free(escaped_bkv);
        if (escaped_hs) curl_free(escaped_hs);
        if (escaped_hsi) curl_free(escaped_hsi);
        if (escaped_s) curl_free(escaped_s);
        if (escaped_dyn) curl_free(escaped_dyn);
        if (escaped_csr) curl_free(escaped_csr);
        if (escaped_rev) curl_free(escaped_rev);
        if (escaped_spin_t) curl_free(escaped_spin_t);
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        return CURLE_OUT_OF_MEMORY;
    }

    if (escaped_bkv != NULL) {
        snprintf(
            url,
            sizeof(url),
            "https://www.instagram.com/async/wbloks/fetch/"
            "?appid=%s&type=%s&__bkv=%s",
            escaped_app_id,
            escaped_type,
            escaped_bkv
        );
    } else {
        snprintf(
            url,
            sizeof(url),
            "https://www.instagram.com/async/wbloks/fetch/"
            "?appid=%s&type=%s",
            escaped_app_id,
            escaped_type
        );
    }

    post_size =
        strlen(escaped_dtsg) +
        strlen(escaped_jazoest) +
        strlen(escaped_lsd) +
        strlen(escaped_params) +
        strlen(escaped_hs) +
        strlen(escaped_hsi) +
        strlen(escaped_s) +
        strlen(escaped_dyn) +
        strlen(escaped_csr) +
        strlen(escaped_rev) +
        strlen(escaped_spin_t) +
        1024;

    post_fields =
        (char *)malloc(post_size);

    if (post_fields == NULL) {
        curl_free(escaped_dtsg);
        curl_free(escaped_jazoest);
        curl_free(escaped_lsd);
        curl_free(escaped_params);
        curl_free(escaped_app_id);
        curl_free(escaped_type);
        if (escaped_bkv) curl_free(escaped_bkv);
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        return CURLE_OUT_OF_MEMORY;
    }

    snprintf(
        post_fields,
        post_size,
        "__d=www"
        "&__user=0"
        "&__a=1"
        "&__req=12"
        "&__hs=%s"
        "&dpr=1"
        "&__ccg=GOOD"
        "&__rev=%s"
        "&__s=%s"
        "&__hsi=%s"
        "&__dyn=%s"
        "&__csr=%s"
        "&__comet_req=7"
        "&fb_dtsg=%s"
        "&jazoest=%s"
        "&lsd=%s"
        "&__spin_r=%s"
        "&__spin_b=trunk"
        "&__spin_t=%s"
        "&__crn=comet.igweb.PolarisYourActivityInteractionsRoute"
        "&params=%s",
        escaped_hs,
        escaped_rev,
        escaped_s,
        escaped_hsi,
        escaped_dyn,
        escaped_csr,
        escaped_dtsg,
        escaped_jazoest,
        escaped_lsd,
        escaped_rev,
        escaped_spin_t,
        escaped_params
    );

    curl_easy_setopt(
        curl,
        CURLOPT_URL,
        url
    );
    curl_easy_setopt(
        curl,
        CURLOPT_HTTPHEADER,
        headers
    );
    curl_easy_setopt(
        curl,
        CURLOPT_POST,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_POSTFIELDS,
        post_fields
    );
    curl_easy_setopt(
        curl,
        CURLOPT_POSTFIELDSIZE,
        (long)strlen(post_fields)
    );
    curl_easy_setopt(
        curl,
        CURLOPT_FOLLOWLOCATION,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_MAXREDIRS,
        5L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_CONNECTTIMEOUT,
        20L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_TIMEOUT,
        45L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_NOSIGNAL,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_SSL_VERIFYPEER,
        1L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_SSL_VERIFYHOST,
        2L
    );
    curl_easy_setopt(
        curl,
        CURLOPT_CAINFO,
        ca_path
    );
    curl_easy_setopt(
        curl,
        CURLOPT_ACCEPT_ENCODING,
        ""
    );
    curl_easy_setopt(
        curl,
        CURLOPT_WRITEFUNCTION,
        magnistra_explore_search_write
    );
    curl_easy_setopt(
        curl,
        CURLOPT_WRITEDATA,
        &g_search_body
    );

    if (user_agent != NULL && user_agent[0] != 0) {
        curl_easy_setopt(
            curl,
            CURLOPT_USERAGENT,
            user_agent
        );
    }

    if (cookies != NULL && cookies[0] != 0) {
        curl_easy_setopt(
            curl,
            CURLOPT_COOKIE,
            cookies
        );
    }

    code = curl_easy_perform(curl);

    curl_easy_getinfo(
        curl,
        CURLINFO_RESPONSE_CODE,
        &g_search_status
    );
    curl_easy_getinfo(
        curl,
        CURLINFO_SSL_VERIFYRESULT,
        &g_search_verify
    );

    free(post_fields);
    curl_free(escaped_dtsg);
    curl_free(escaped_jazoest);
    curl_free(escaped_lsd);
    curl_free(escaped_params);
    curl_free(escaped_app_id);
    curl_free(escaped_type);
    if (escaped_bkv) curl_free(escaped_bkv);
    curl_free(escaped_hs);
    curl_free(escaped_hsi);
    curl_free(escaped_s);
    curl_free(escaped_dyn);
    curl_free(escaped_csr);
    curl_free(escaped_rev);
    curl_free(escaped_spin_t);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return code;
}

int magnistra_explore_wbloks_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *app_id,
    const char *request_type,
    const char *params_json
) {
    CURLcode code;
    char fb_dtsg[1024];
    char jazoest[2048];
    char lsd[1024];
    char bkv[1024];
    int jazoest_ok = 0;

    if (
        ca_path == NULL ||
        ca_path[0] == 0 ||
        user_agent == NULL ||
        user_agent[0] == 0 ||
        cookies == NULL ||
        cookies[0] == 0 ||
        csrf_token == NULL ||
        csrf_token[0] == 0 ||
        app_id == NULL ||
        app_id[0] == 0 ||
        request_type == NULL ||
        request_type[0] == 0 ||
        params_json == NULL ||
        params_json[0] == 0
    ) {
        return -9510;
    }

    fb_dtsg[0] = 0;
    jazoest[0] = 0;
    lsd[0] = 0;
    bkv[0] = 0;

    code =
        curl_global_init(
            CURL_GLOBAL_DEFAULT
        );

    if (code != CURLE_OK) {
        return (int)code;
    }

    code =
        magnistra_explore_search_get_root(
            ca_path,
            user_agent,
            language,
            cookies,
            csrf_token
        );

    if (
        code != CURLE_OK ||
        g_search_status < 200 ||
        g_search_status >= 300 ||
        g_search_body.data == NULL ||
        g_search_body.size == 0
    ) {
        curl_global_cleanup();
        return (int)code;
    }

    if (
        !magnistra_explore_search_extract_fb_dtsg(
            (const char *)g_search_body.data,
            fb_dtsg,
            sizeof(fb_dtsg)
        )
    ) {
        g_search_status = 478;
        curl_global_cleanup();
        return (int)CURLE_GOT_NOTHING;
    }

    jazoest_ok =
        magnistra_explore_search_extract_jazoest(
            (const char *)g_search_body.data,
            jazoest,
            sizeof(jazoest)
        );

    if (!jazoest_ok) {
        jazoest_ok =
            magnistra_explore_search_derive_jazoest(
                fb_dtsg,
                jazoest,
                sizeof(jazoest)
            );
    }

    if (!jazoest_ok) {
        g_search_status = 479;
        curl_global_cleanup();
        return (int)CURLE_GOT_NOTHING;
    }

    if (
        !magnistra_explore_wbloks_extract_lsd(
            (const char *)g_search_body.data,
            lsd,
            sizeof(lsd)
        )
    ) {
        g_search_status = 480;
        curl_global_cleanup();
        return (int)CURLE_GOT_NOTHING;
    }

    (void)magnistra_explore_wbloks_extract_bkv(
        (const char *)g_search_body.data,
        bkv,
        sizeof(bkv)
    );

    magnistra_wbloks_dynamic_extract(
        (const char *)g_search_body.data
    );

    const char *effective_request_type =
        request_type;

    if (
        app_id != NULL &&
        strcmp(
            app_id,
            "com.instagram.privacy.activity_center.liked_media_screen"
        ) == 0
    ) {
        effective_request_type =
            "app";
    }

    code =
        magnistra_explore_wbloks_post(
            ca_path,
            user_agent,
            language,
            cookies,
            csrf_token,
            fb_dtsg,
            jazoest,
            lsd,
            bkv,
            app_id,
            effective_request_type,
            params_json
        );

    memset(fb_dtsg, 0, sizeof(fb_dtsg));
    memset(jazoest, 0, sizeof(jazoest));
    memset(lsd, 0, sizeof(lsd));
    memset(bkv, 0, sizeof(bkv));

    curl_global_cleanup();

    if (
        code == CURLE_OK &&
        g_search_status >= 200 &&
        g_search_status < 300 &&
        g_search_verify == 0
    ) {
        return 0;
    }

    return (int)code;
}

long magnistra_explore_search_http_status(void) {
    return g_search_status;
}

long magnistra_explore_search_tls_verify_result(void) {
    return g_search_verify;
}

long long magnistra_explore_search_body_length(void) {
    return (long long)g_search_body.size;
}

const unsigned char *magnistra_explore_search_body(void) {
    return g_search_body.data;
}

int magnistra_explore_rest_get(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *url
) {
    CURL *curl = NULL;
    CURLcode code = CURLE_FAILED_INIT;
    struct curl_slist *headers = NULL;

    if (
        ca_path == NULL ||
        ca_path[0] == 0 ||
        user_agent == NULL ||
        user_agent[0] == 0 ||
        cookies == NULL ||
        cookies[0] == 0 ||
        csrf_token == NULL ||
        csrf_token[0] == 0 ||
        url == NULL ||
        url[0] == 0
    ) {
        return -9520;
    }

    code = curl_global_init(CURL_GLOBAL_DEFAULT);

    if (code != CURLE_OK) {
        return (int)code;
    }

    magnistra_explore_search_reset();

    curl = curl_easy_init();

    if (curl == NULL) {
        curl_global_cleanup();
        return (int)CURLE_FAILED_INIT;
    }

    if (strcmp(url, "https://www.instagram.com/") == 0) {
        char language_header[2048];
        headers = curl_slist_append(headers,
            "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
        headers = curl_slist_append(headers,
            "Sec-Fetch-Site: none");
        headers = curl_slist_append(headers,
            "Sec-Fetch-Mode: navigate");
        headers = curl_slist_append(headers,
            "Sec-Fetch-Dest: document");
        headers = curl_slist_append(headers,
            "Upgrade-Insecure-Requests: 1");
        if (language != NULL && language[0] != 0) {
            snprintf(language_header, sizeof(language_header),
                "Accept-Language: %s", language);
            headers = curl_slist_append(headers, language_header);
        }
    } else {
        headers = magnistra_explore_search_headers(
            language,
            csrf_token,
            NULL
        );
    }

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 5L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 20L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 45L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(curl, CURLOPT_CAINFO, ca_path);
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
    curl_easy_setopt(
        curl,
        CURLOPT_WRITEFUNCTION,
        magnistra_explore_search_write
    );
    curl_easy_setopt(
        curl,
        CURLOPT_WRITEDATA,
        &g_search_body
    );
    curl_easy_setopt(curl, CURLOPT_USERAGENT, user_agent);
    curl_easy_setopt(curl, CURLOPT_COOKIE, cookies);

    code = curl_easy_perform(curl);

    curl_easy_getinfo(
        curl,
        CURLINFO_RESPONSE_CODE,
        &g_search_status
    );
    curl_easy_getinfo(
        curl,
        CURLINFO_SSL_VERIFYRESULT,
        &g_search_verify
    );

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    curl_global_cleanup();

    return (int)code;
}

static int g_archive_web_fields = 0;
static int g_archive_header_bytes = 0;
static int g_archive_mime_kind = 0;

int magnistra_archive_web_fields(void) { return g_archive_web_fields; }
int magnistra_archive_header_bytes(void) { return g_archive_header_bytes; }
int magnistra_archive_mime_kind(void) { return g_archive_mime_kind; }

static int magnistra_archive_append_query(CURL *curl, char *dst, size_t cap,
                                         const char *key, const char *value) {
    char *escaped;
    size_t n, k, v;
    if (!value || !value[0]) return 1;
    escaped = curl_easy_escape(curl, value, 0);
    if (!escaped) return 0;
    n = strlen(dst); k = strlen(key); v = strlen(escaped);
    if (n + k + v + 3 >= cap) { curl_free(escaped); return 0; }
    snprintf(dst + n, cap - n, "&%s=%s", key, escaped);
    curl_free(escaped);
    g_archive_web_fields++;
    return 1;
}

int magnistra_archive_web_read(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *url,
    const char *encoded_post_body
) {
    CURL *curl = NULL;
    CURLcode result;
    struct curl_slist *headers = NULL;
    char language_header[512];
    char csrf_header[2048];
    char fb_dtsg[1024] = {0};
    char jazoest[2048] = {0};
    char *escaped_dtsg = NULL;
    char *escaped_jazoest = NULL;
    char *body = NULL;
    int is_post = encoded_post_body != NULL;
    size_t size = 0;
    char *request_url = NULL;
    long header_size = 0;
    char *content_type = NULL;
    int is_archive_get = !is_post && strstr(url, "/api/v1/archive/reel/day_shells/") != NULL;

    g_archive_web_fields = 0;
    g_archive_header_bytes = 0;
    g_archive_mime_kind = 0;
    magnistra_explore_search_reset();
    if (!ca_path || !ca_path[0] || !user_agent || !user_agent[0] ||
        !cookies || !cookies[0] || !csrf_token || !csrf_token[0] ||
        !url || !url[0]) return -9701;
    if (strncmp(url, "https://www.instagram.com/api/v1/archive/reel/day_shells/", strlen("https://www.instagram.com/api/v1/archive/reel/day_shells/")) != 0 &&
        strncmp(url, "https://www.instagram.com/api/v1/feed/reels_media/",
                strlen("https://www.instagram.com/api/v1/feed/reels_media/")) != 0) return -9702;
    if (strlen(url) > 1600) return -9704;
    if (is_post && (strcmp(url, "https://www.instagram.com/api/v1/feed/reels_media/") != 0 ||
                    strlen(encoded_post_body) > 1024 ||
                    strncmp(encoded_post_body, "reel_ids=", 9) != 0)) return -9703;
    result = curl_global_init(CURL_GLOBAL_DEFAULT);
    if (result != CURLE_OK) return (int)result;

    if (is_archive_get) {

        CURLcode bootstrap = magnistra_explore_search_get_root(
            ca_path, user_agent, language, cookies, csrf_token);
        if (bootstrap == CURLE_OK && g_search_status >= 200 &&
            g_search_status < 300 && g_search_body.data && g_search_body.size) {
            CURL *encoder = curl_easy_init();
            if (encoder) {
                size_t cap = 32768;
                request_url = (char *)calloc(1, cap);
                if (!request_url) { curl_easy_cleanup(encoder); result = CURLE_OUT_OF_MEMORY; goto archive_done; }
                snprintf(request_url, cap, "%s", url);
                magnistra_wbloks_dynamic_extract((const char *)g_search_body.data);

                char active_dtsg[1024] = {0};
                char active_jazoest[2048] = {0};
                (void)magnistra_explore_search_extract_fb_dtsg(
                    (const char *)g_search_body.data, active_dtsg, sizeof(active_dtsg));
                (void)magnistra_explore_search_extract_jazoest(
                    (const char *)g_search_body.data, active_jazoest, sizeof(active_jazoest));
                if (active_dtsg[0] && !active_jazoest[0])
                    (void)magnistra_explore_search_derive_jazoest(
                        active_dtsg, active_jazoest, sizeof(active_jazoest));

                if (!magnistra_archive_append_query(encoder, request_url, cap, "__hs", g_magnistra_wbloks_hs) ||
                    !magnistra_archive_append_query(encoder, request_url, cap, "__hsi", g_magnistra_wbloks_hsi) ||
                    !magnistra_archive_append_query(encoder, request_url, cap, "__s", g_magnistra_wbloks_s) ||
                    !magnistra_archive_append_query(encoder, request_url, cap, "__dyn", g_magnistra_wbloks_dyn) ||
                    !magnistra_archive_append_query(encoder, request_url, cap, "__csr", g_magnistra_wbloks_csr) ||
                    !magnistra_archive_append_query(encoder, request_url, cap, "__rev", g_magnistra_wbloks_rev) ||
                    !magnistra_archive_append_query(encoder, request_url, cap, "__spin_r", g_magnistra_wbloks_rev) ||
                    !magnistra_archive_append_query(encoder, request_url, cap, "__spin_t", g_magnistra_wbloks_spin_t) ||
                    !magnistra_archive_append_query(encoder, request_url, cap, "jazoest", active_jazoest)) {
                    memset(active_dtsg, 0, sizeof(active_dtsg));
                    memset(active_jazoest, 0, sizeof(active_jazoest));
                    curl_easy_cleanup(encoder);
                    result = CURLE_OUT_OF_MEMORY;
                    goto archive_done;
                }
                memset(active_dtsg, 0, sizeof(active_dtsg));
                memset(active_jazoest, 0, sizeof(active_jazoest));
                curl_easy_cleanup(encoder);
            }
        }

    }

    if (is_post) {
        result = magnistra_explore_search_get_root(
            ca_path, user_agent, language, cookies, csrf_token);
        if (result != CURLE_OK || g_search_status < 200 || g_search_status >= 300 ||
            !g_search_body.data || !g_search_body.size) {
            if (result == CURLE_OK) result = CURLE_GOT_NOTHING;
            goto archive_done;
        }
        if (!magnistra_explore_search_extract_fb_dtsg(
                (const char *)g_search_body.data, fb_dtsg, sizeof(fb_dtsg))) {
            g_search_status = 497;
            result = CURLE_GOT_NOTHING;
            goto archive_done;
        }
        if (!magnistra_explore_search_extract_jazoest(
                (const char *)g_search_body.data, jazoest, sizeof(jazoest)) &&
            !magnistra_explore_search_derive_jazoest(
                fb_dtsg, jazoest, sizeof(jazoest))) {
            g_search_status = 498;
            result = CURLE_GOT_NOTHING;
            goto archive_done;
        }
    }

    magnistra_explore_search_reset();
    curl = curl_easy_init();
    if (!curl) {
        result = CURLE_FAILED_INIT;
        goto archive_done;
    }
    headers = curl_slist_append(headers, "Accept: */*");
    headers = curl_slist_append(headers, "Referer: https://www.instagram.com/archive/stories/");
    headers = curl_slist_append(headers, "X-ASBD-ID: 359341");
    headers = curl_slist_append(headers, "Sec-Fetch-Site: same-origin");
    headers = curl_slist_append(headers, "Sec-Fetch-Mode: cors");
    headers = curl_slist_append(headers, "Sec-Fetch-Dest: empty");
    if (language && language[0]) {
        snprintf(language_header, sizeof(language_header), "Accept-Language: %s", language);
        headers = curl_slist_append(headers, language_header);
    }
    if (is_post) {
        snprintf(csrf_header, sizeof(csrf_header), "X-CSRFToken: %s", csrf_token);
        headers = curl_slist_append(headers, csrf_header);
        headers = curl_slist_append(headers, "X-IG-App-ID: 1217981644879628");
        headers = curl_slist_append(headers, "Origin: https://www.instagram.com");
        headers = curl_slist_append(headers, "Content-Type: application/x-www-form-urlencoded");
        escaped_dtsg = curl_easy_escape(curl, fb_dtsg, 0);
        escaped_jazoest = curl_easy_escape(curl, jazoest, 0);
        if (!escaped_dtsg || !escaped_jazoest) {
            result = CURLE_OUT_OF_MEMORY;
            goto archive_done;
        }
        size = strlen(escaped_dtsg) + strlen(escaped_jazoest) +
               strlen(encoded_post_body) + 30;
        body = (char *)calloc(1, size);
        if (!body) {
            result = CURLE_OUT_OF_MEMORY;
            goto archive_done;
        }
        snprintf(body, size, "fb_dtsg=%s&jazoest=%s&%s", escaped_dtsg,
                 escaped_jazoest, encoded_post_body);
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)strlen(body));
    }
    curl_easy_setopt(curl, CURLOPT_URL, request_url ? request_url : url);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, user_agent);
    curl_easy_setopt(curl, CURLOPT_COOKIE, cookies);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 20L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 45L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(curl, CURLOPT_CAINFO, ca_path);
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, magnistra_explore_search_write);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &g_search_body);
    result = curl_easy_perform(curl);
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &g_search_status);
    curl_easy_getinfo(curl, CURLINFO_SSL_VERIFYRESULT, &g_search_verify);
    curl_easy_getinfo(curl, CURLINFO_HEADER_SIZE, &header_size);
    g_archive_header_bytes = header_size > 0 && header_size < 1000000 ? (int)header_size : 0;
    curl_easy_getinfo(curl, CURLINFO_CONTENT_TYPE, &content_type);
    if (content_type) {
        if (strstr(content_type, "json")) g_archive_mime_kind = 1;
        else if (strstr(content_type, "html")) g_archive_mime_kind = 2;
        else g_archive_mime_kind = 3;
    }
archive_done:
    if (request_url) { memset(request_url, 0, strlen(request_url)); free(request_url); }
    if (body) { memset(body, 0, strlen(body)); free(body); }
    if (escaped_dtsg) curl_free(escaped_dtsg);
    if (escaped_jazoest) curl_free(escaped_jazoest);
    memset(fb_dtsg, 0, sizeof(fb_dtsg));
    memset(jazoest, 0, sizeof(jazoest));
    if (headers) curl_slist_free_all(headers);
    if (curl) curl_easy_cleanup(curl);
    curl_global_cleanup();
    return (int)result;
}

long magnistra_explore_http_status(void) {
    return g_status;
}

long magnistra_explore_tls_verify_result(void) {
    return g_verify;
}

long long magnistra_explore_body_length(void) {
    return (long long)g_body.size;
}

const unsigned char *magnistra_explore_body(void) {
    return g_body.data;
}

typedef struct MagnistraDirectMediaBuffer {
    unsigned char *data;
    size_t size;
    size_t capacity;
} MagnistraDirectMediaBuffer;

static MagnistraDirectMediaBuffer g_direct_media_body = {
    NULL,
    0,
    0
};

static long g_direct_media_status = 0;
static long g_direct_media_verify = -1;

static void magnistra_direct_media_reset(void) {
    if (g_direct_media_body.data != NULL) {
        free(g_direct_media_body.data);
    }

    g_direct_media_body.data = NULL;
    g_direct_media_body.size = 0;
    g_direct_media_body.capacity = 0;
    g_direct_media_status = 0;
    g_direct_media_verify = -1;
}

static size_t magnistra_direct_media_write(
    char *ptr,
    size_t size,
    size_t nmemb,
    void *userdata
) {
    MagnistraDirectMediaBuffer *buffer =
        (MagnistraDirectMediaBuffer *)userdata;

    size_t incoming = size * nmemb;
    size_t wanted;
    size_t next;
    unsigned char *grown;

    if (incoming == 0) {
        return 0;
    }

    wanted = buffer->size + incoming + 1;

    if (wanted > buffer->capacity) {
        next =
            buffer->capacity
                ? buffer->capacity
                : 4096;

        while (next < wanted) {
            next *= 2;
        }

        grown =
            (unsigned char *)realloc(
                buffer->data,
                next
            );

        if (grown == NULL) {
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

int magnistra_direct_media_upload(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *file_path,
    const char *file_name,
    const char *mime_type,
    int voice_clip
) {
    CURL *easy = NULL;
    CURLcode rc;
    struct curl_slist *headers = NULL;
    struct curl_httppost *form = NULL;
    struct curl_httppost *last = NULL;
    char csrf_header[2048];
    char language_header[512];

    magnistra_direct_media_reset();

    if (
        ca_path == NULL ||
        user_agent == NULL ||
        cookie_header == NULL ||
        csrf_token == NULL ||
        file_path == NULL ||
        file_name == NULL ||
        mime_type == NULL ||
        ca_path[0] == '\0' ||
        user_agent[0] == '\0' ||
        cookie_header[0] == '\0' ||
        csrf_token[0] == '\0' ||
        file_path[0] == '\0' ||
        file_name[0] == '\0' ||
        mime_type[0] == '\0'
    ) {
        return -7300;
    }

    rc = curl_global_init(CURL_GLOBAL_DEFAULT);

    if (rc != CURLE_OK) {
        return (int)rc;
    }

    easy = curl_easy_init();

    if (easy == NULL) {
        curl_global_cleanup();
        return -7301;
    }

    curl_formadd(
        &form,
        &last,
        CURLFORM_COPYNAME,
        "farr",
        CURLFORM_FILE,
        file_path,
        CURLFORM_FILENAME,
        "blob",
        CURLFORM_CONTENTTYPE,
        mime_type,
        CURLFORM_END
    );

    if (voice_clip) {
        curl_formadd(
            &form,
            &last,
            CURLFORM_COPYNAME,
            "voice_clip",
            CURLFORM_COPYCONTENTS,
            "true",
            CURLFORM_END
        );
    }

    snprintf(
        csrf_header,
        sizeof(csrf_header),
        "X-CSRFToken: %s",
        csrf_token
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

    headers = curl_slist_append(
        headers,
        "Accept: */*"
    );

    headers = curl_slist_append(
        headers,
        "Origin: https://www.instagram.com"
    );

    headers = curl_slist_append(
        headers,
        "Referer: https://www.instagram.com/direct/inbox/"
    );

    headers = curl_slist_append(
        headers,
        "X-IG-App-ID: 936619743392459"
    );

    headers = curl_slist_append(
        headers,
        "X-ASBD-ID: 198387"
    );

    headers = curl_slist_append(
        headers,
        "Sec-Fetch-Site: same-origin"
    );

    headers = curl_slist_append(
        headers,
        "Sec-Fetch-Mode: cors"
    );

    headers = curl_slist_append(
        headers,
        "Sec-Fetch-Dest: empty"
    );

    headers = curl_slist_append(
        headers,
        "X-Requested-With: XMLHttpRequest"
    );

    headers = curl_slist_append(
        headers,
        "Expect:"
    );

    headers = curl_slist_append(
        headers,
        csrf_header
    );

    headers = curl_slist_append(
        headers,
        language_header
    );

    curl_easy_setopt(
        easy,
        CURLOPT_URL,
        "https://www.instagram.com/ajax/mercury/upload.php"
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
        CURLOPT_HTTPPOST,
        form
    );

    curl_easy_setopt(
        easy,
        CURLOPT_FOLLOWLOCATION,
        0L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_CONNECTTIMEOUT,
        20L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_TIMEOUT,
        240L
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
        magnistra_direct_media_write
    );

    curl_easy_setopt(
        easy,
        CURLOPT_WRITEDATA,
        &g_direct_media_body
    );

    rc = curl_easy_perform(easy);

    curl_easy_getinfo(
        easy,
        CURLINFO_RESPONSE_CODE,
        &g_direct_media_status
    );

    curl_easy_getinfo(
        easy,
        CURLINFO_SSL_VERIFYRESULT,
        &g_direct_media_verify
    );

    if (headers != NULL) {
        curl_slist_free_all(headers);
    }

    if (form != NULL) {
        curl_formfree(form);
    }

    curl_easy_cleanup(easy);
    curl_global_cleanup();

    return (int)rc;
}

long magnistra_direct_media_http_status(void) {
    return g_direct_media_status;
}

long magnistra_direct_media_tls_verify_result(void) {
    return g_direct_media_verify;
}

long long magnistra_direct_media_body_length(void) {
    return (long long)g_direct_media_body.size;
}

const unsigned char *magnistra_direct_media_body(void) {
    return g_direct_media_body.data;
}

#include <curl/curl.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

extern int magnistra_curl_process_init_once(void);
#ifdef curl_global_init
#undef curl_global_init
#endif
#ifdef curl_global_cleanup
#undef curl_global_cleanup
#endif
#define curl_global_init(...) ((CURLcode)magnistra_curl_process_init_once())
#define curl_global_cleanup() ((void)0)

static unsigned char *mg_direct_media_result = NULL;
static size_t mg_direct_media_length = 0;
static long mg_direct_media_status = 0;
static char mg_direct_media_type[64] = "unknown";
static int mg_direct_media_same_endpoint = 0;
const char *magnistra_direct_media_upload_response_type(void) { return mg_direct_media_type; }
int magnistra_direct_media_upload_endpoint_matches(void) { return mg_direct_media_same_endpoint; }

static size_t mg_direct_media_write(char *ptr,size_t size,size_t count,void *userdata) {
    size_t n=size*count;
    (void)userdata;
    if (!n || n > 4*1024*1024 || mg_direct_media_length > 4*1024*1024-n) return 0;
    unsigned char *p=(unsigned char *)realloc(mg_direct_media_result,mg_direct_media_length+n+1);
    if (!p)return 0;
    mg_direct_media_result=p;
    memcpy(p+mg_direct_media_length,ptr,n);
    mg_direct_media_length+=n;
    p[mg_direct_media_length]=0;
    return n;
}

const unsigned char *magnistra_direct_media_response_data(void) { return mg_direct_media_result; }
size_t magnistra_direct_media_response_length(void) { return mg_direct_media_length; }
long magnistra_direct_media_upload_http_status(void) { return mg_direct_media_status; }

int magnistra_direct_media_upload_curl(
    const char *ca, const char *ua, const char *lang,
    const char *cookie, const char *csrf, const char *content_type,
    const unsigned char *data, size_t length) {
    CURL *curl=NULL;
    struct curl_slist *headers=NULL;
    CURLcode rc=CURLE_FAILED_INIT;
    char typehdr[160],tokenhdr[2048],languagehdr[512];
    if(mg_direct_media_result){free(mg_direct_media_result);mg_direct_media_result=NULL;}
    mg_direct_media_length=0;mg_direct_media_status=0;mg_direct_media_same_endpoint=0;strcpy(mg_direct_media_type,"unknown");
    if(!ca||!ca[0]||!ua||!ua[0]||!cookie||!cookie[0]||!csrf||!csrf[0]
       ||!content_type||!data||!length||length>20*1024*1024) return -7201;
    if(strlen(csrf)>1800||strlen(content_type)>110) return -7202;
    curl=curl_easy_init();if(!curl) return -7203;
    snprintf(typehdr,sizeof(typehdr),"Content-Type: %s",content_type);
    snprintf(tokenhdr,sizeof(tokenhdr),"X-CSRFToken: %s",csrf);
    headers=curl_slist_append(headers,"Accept: */*");
    headers=curl_slist_append(headers,"Origin: https://www.instagram.com");
    headers=curl_slist_append(headers,"Referer: https://www.instagram.com/direct/inbox/");
    headers=curl_slist_append(headers,"X-Requested-With: XMLHttpRequest");
    headers=curl_slist_append(headers,"Sec-Fetch-Site: same-origin");
    headers=curl_slist_append(headers,"Sec-Fetch-Mode: cors");
    headers=curl_slist_append(headers,"Sec-Fetch-Dest: empty");
    headers=curl_slist_append(headers,"X-IG-App-ID: 936619743392459");
    headers=curl_slist_append(headers,"Expect:");
    headers=curl_slist_append(headers,typehdr);
    headers=curl_slist_append(headers,tokenhdr);
    if(lang&&lang[0]){
        snprintf(languagehdr,sizeof(languagehdr),"Accept-Language: %.475s",lang);
        headers=curl_slist_append(headers,languagehdr);
    }
    curl_easy_setopt(curl,CURLOPT_URL,"https://www.instagram.com/ajax/mercury/upload.php");
    curl_easy_setopt(curl,CURLOPT_POST,1L);
    curl_easy_setopt(curl,CURLOPT_POSTFIELDS,(const char *)data);
    curl_easy_setopt(curl,CURLOPT_POSTFIELDSIZE_LARGE,(curl_off_t)length);
    curl_easy_setopt(curl,CURLOPT_HTTPHEADER,headers);
    curl_easy_setopt(curl,CURLOPT_USERAGENT,ua);
    curl_easy_setopt(curl,CURLOPT_COOKIE,cookie);
    curl_easy_setopt(curl,CURLOPT_CAINFO,ca);
    curl_easy_setopt(curl,CURLOPT_SSL_VERIFYPEER,1L);
    curl_easy_setopt(curl,CURLOPT_SSL_VERIFYHOST,2L);
    curl_easy_setopt(curl,CURLOPT_FOLLOWLOCATION,0L);
    curl_easy_setopt(curl,CURLOPT_NOSIGNAL,1L);
    curl_easy_setopt(curl,CURLOPT_CONNECTTIMEOUT,15L);
    curl_easy_setopt(curl,CURLOPT_TIMEOUT,75L);
    curl_easy_setopt(curl,CURLOPT_WRITEFUNCTION,mg_direct_media_write);
    curl_easy_setopt(curl,CURLOPT_ACCEPT_ENCODING,"");
    rc=curl_easy_perform(curl);
    curl_easy_getinfo(curl,CURLINFO_RESPONSE_CODE,&mg_direct_media_status);
    {
        char *response_type = NULL;
        char *effective_url = NULL;
        curl_easy_getinfo(curl,CURLINFO_CONTENT_TYPE,&response_type);
        curl_easy_getinfo(curl,CURLINFO_EFFECTIVE_URL,&effective_url);
        mg_direct_media_same_endpoint = effective_url &&
            strcmp(effective_url,"https://www.instagram.com/ajax/mercury/upload.php")==0;
        strcpy(mg_direct_media_type,"unknown");
        if(response_type) {
            size_t n = strcspn(response_type,";\r\n");
            if(n>=sizeof(mg_direct_media_type))n=sizeof(mg_direct_media_type)-1;
            memcpy(mg_direct_media_type,response_type,n);
            mg_direct_media_type[n]=0;
        }
    }
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return (int)rc;
}

static char mg_direct_form_dtsg[1024];
static char mg_direct_form_jazoest[2048];
const char *magnistra_direct_media_auth_dtsg(void) { return mg_direct_form_dtsg; }
const char *magnistra_direct_media_auth_jazoest(void) { return mg_direct_form_jazoest; }
int magnistra_direct_media_prepare_auth(
    const char *ca, const char *ua, const char *lang,
    const char *cookies, const char *csrf) {
    CURLcode rc;
    int jaz_ok;
    mg_direct_form_dtsg[0]=0;
    mg_direct_form_jazoest[0]=0;
    if (!ca||!ca[0]||!ua||!ua[0]||!cookies||!cookies[0]||!csrf||!csrf[0]) return -7401;
    rc=curl_global_init(CURL_GLOBAL_DEFAULT);
    if (rc!=CURLE_OK) return -7402;
    rc=magnistra_explore_search_get_root(ca,ua,lang,cookies,csrf);
    if (rc!=CURLE_OK || g_search_status<200 || g_search_status>=300 ||
        !g_search_body.data || !g_search_body.size) {
        curl_global_cleanup();
        return -7403;
    }
    if (!magnistra_explore_search_extract_fb_dtsg(
           (const char *)g_search_body.data,mg_direct_form_dtsg,sizeof(mg_direct_form_dtsg))) {
        curl_global_cleanup();
        return -7404;
    }
    jaz_ok=magnistra_explore_search_extract_jazoest(
        (const char *)g_search_body.data,mg_direct_form_jazoest,sizeof(mg_direct_form_jazoest));
    if (!jaz_ok) jaz_ok=magnistra_explore_search_derive_jazoest(
        mg_direct_form_dtsg,mg_direct_form_jazoest,sizeof(mg_direct_form_jazoest));
    curl_global_cleanup();
    if (!jaz_ok) return -7405;

    if(strpbrk(mg_direct_form_dtsg,"\r\n")||strpbrk(mg_direct_form_jazoest,"\r\n")) return -7406;
    return 0;
}
