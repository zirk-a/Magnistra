#include "ProfileMediaTransport.h"

#include <curl/curl.h>
#include <stdint.h>
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
} Buffer;

static Buffer g_body = {0};
static long g_status = 0;
static long g_verify = -1;

static const char *k_mobile_ua =
    "Instagram 446.0.0.49.77 Android "
    "(34/14; 480dpi; 1344x2992; Google/google; "
    "Pixel 8 Pro; husky; husky; en_US; 385211303)";

static void reset_state(void) {
    free(g_body.data);
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
    size_t count = size * nmemb;
    Buffer *buffer = (Buffer *)userdata;
    size_t required;
    size_t capacity;
    unsigned char *next;

    if (count == 0) {
        return 0;
    }

    required = buffer->size + count + 1;

    if (required > buffer->capacity) {
        capacity =
            buffer->capacity
                ? buffer->capacity
                : 32768;

        while (capacity < required) {
            capacity *= 2;

            if (capacity > 16 * 1024 * 1024) {
                return 0;
            }
        }

        next =
            (unsigned char *)
                realloc(
                    buffer->data,
                    capacity
                );

        if (!next) {
            return 0;
        }

        buffer->data = next;
        buffer->capacity = capacity;
    }

    memcpy(
        buffer->data + buffer->size,
        ptr,
        count
    );

    buffer->size += count;
    buffer->data[buffer->size] = 0;

    return count;
}

static uint64_t fnv1a64(
    const char *s
) {
    uint64_t h =
        1469598103934665603ULL;

    while (s && *s) {
        h ^= (unsigned char)*s++;
        h *= 1099511628211ULL;
    }

    return h;
}

static void device_values(
    const char *user_id,
    char *device_uuid,
    size_t device_uuid_size,
    char *family_uuid,
    size_t family_uuid_size,
    char *android_id,
    size_t android_id_size
) {
    uint64_t a =
        fnv1a64(
            user_id
        );

    uint64_t b =
        a ^
        0x9e3779b97f4a7c15ULL;

    snprintf(
        device_uuid,
        device_uuid_size,
        "%08x-%04x-4%03x-a%03x-%012llx",
        (unsigned)(a >> 32),
        (unsigned)((a >> 16) & 0xffff),
        (unsigned)(a & 0x0fff),
        (unsigned)((b >> 48) & 0x0fff),
        (unsigned long long)(
            b &
            0xffffffffffffULL
        )
    );

    snprintf(
        family_uuid,
        family_uuid_size,
        "%08x-%04x-4%03x-b%03x-%012llx",
        (unsigned)(b >> 32),
        (unsigned)((b >> 16) & 0xffff),
        (unsigned)(b & 0x0fff),
        (unsigned)((a >> 48) & 0x0fff),
        (unsigned long long)(
            a &
            0xffffffffffffULL
        )
    );

    snprintf(
        android_id,
        android_id_size,
        "android-%016llx",
        (unsigned long long)a
    );
}

static int cookie_value(
    const char *cookie_header,
    const char *name,
    char *out,
    size_t out_size
) {
    const char *p;
    size_t name_len;

    if (
        !cookie_header ||
        !name ||
        !out ||
        out_size == 0
    ) {
        return 0;
    }

    name_len =
        strlen(
            name
        );

    p =
        cookie_header;

    while (*p) {
        const char *start;
        const char *end;
        size_t len;

        while (
            *p == ' ' ||
            *p == ';'
        ) {
            p++;
        }

        if (
            strncmp(
                p,
                name,
                name_len
            ) == 0 &&
            p[name_len] == '='
        ) {
            start =
                p +
                name_len +
                1;

            end =
                strchr(
                    start,
                    ';'
                );

            if (!end) {
                end =
                    start +
                    strlen(
                        start
                    );
            }

            len =
                (size_t)(
                    end -
                    start
                );

            if (len >= out_size) {
                len =
                    out_size -
                    1;
            }

            memcpy(
                out,
                start,
                len
            );

            out[len] =
                '\0';

            return
                len > 0
                    ? 1
                    : 0;
        }

        p =
            strchr(
                p,
                ';'
            );

        if (!p) {
            break;
        }

        p++;
    }

    return 0;
}

int magnistra_profile_media_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *user_id,
    const char *username,
    const char *max_id,
    int by_username
) {
    CURL *easy = NULL;
    CURLcode rc;
    struct curl_slist *headers = NULL;

    char device_uuid[64];
    char family_uuid[64];
    char android_id[64];

    char language_header[512];
    char csrf_header[1024];
    char device_header[128];
    char family_header[128];
    char android_header[128];

    char mid_value[1024];
    char mid_header[1200];

    char url[8192];
    char *escaped_max_id = NULL;

    (void)user_agent;
    (void)username;
    (void)by_username;

    reset_state();

    if (
        !ca_path ||
        !ca_path[0] ||
        !cookie_header ||
        !cookie_header[0] ||
        !csrf_token ||
        !csrf_token[0] ||
        !user_id ||
        !user_id[0]
    ) {
        return -7200;
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
        return -7201;
    }

    device_values(
        user_id,
        device_uuid,
        sizeof(device_uuid),
        family_uuid,
        sizeof(family_uuid),
        android_id,
        sizeof(android_id)
    );

    snprintf(
        language_header,
        sizeof(language_header),
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

    snprintf(
        device_header,
        sizeof(device_header),
        "X-IG-Device-ID: %s",
        device_uuid
    );

    snprintf(
        family_header,
        sizeof(family_header),
        "X-IG-Family-Device-ID: %s",
        family_uuid
    );

    snprintf(
        android_header,
        sizeof(android_header),
        "X-IG-Android-ID: %s",
        android_id
    );

    if (
        max_id &&
        max_id[0]
    ) {
        escaped_max_id =
            curl_easy_escape(
                easy,
                max_id,
                0
            );

        if (!escaped_max_id) {
            curl_easy_cleanup(easy);
            curl_global_cleanup();
            return -7202;
        }

        snprintf(
            url,
            sizeof(url),
            "https://i.instagram.com/api/v1/feed/user/%s/?count=9&max_id=%s",
            user_id,
            escaped_max_id
        );
    } else {
        snprintf(
            url,
            sizeof(url),
            "https://i.instagram.com/api/v1/feed/user/%s/?count=9",
            user_id
        );
    }

    headers =
        curl_slist_append(
            headers,
            "Accept: */*"
        );

    headers =
        curl_slist_append(
            headers,
            language_header
        );

    headers =
        curl_slist_append(
            headers,
            csrf_header
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-App-ID: 567067343352427"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-App-Locale: en_US"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-Device-Locale: en_US"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-Mapped-Locale: en_US"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-Connection-Type: WIFI"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-Timezone-Offset: 7200"
        );

    headers =
        curl_slist_append(
            headers,
            "X-Bloks-Version-Id: 935a519904e9017324cdedb64a283a3c2c1a3d5b0bbc698b451f5aef72cc11df"
        );

    headers =
        curl_slist_append(
            headers,
            device_header
        );

    headers =
        curl_slist_append(
            headers,
            family_header
        );

    headers =
        curl_slist_append(
            headers,
            android_header
        );

    if (
        cookie_value(
            cookie_header,
            "mid",
            mid_value,
            sizeof(mid_value)
        )
    ) {
        snprintf(
            mid_header,
            sizeof(mid_header),
            "X-MID: %s",
            mid_value
        );

        headers =
            curl_slist_append(
                headers,
                mid_header
            );
    }

    curl_easy_setopt(
        easy,
        CURLOPT_URL,
        url
    );

    curl_easy_setopt(
        easy,
        CURLOPT_USERAGENT,
        k_mobile_ua
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
        CURLOPT_HTTP_CONTENT_DECODING,
        1L
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
        CURLOPT_HTTPGET,
        1L
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

    if (escaped_max_id) {
        curl_free(
            escaped_max_id
        );
    }

    curl_slist_free_all(
        headers
    );

    curl_easy_cleanup(
        easy
    );

    curl_global_cleanup();

    return (int)rc;
}

long magnistra_profile_media_http_status(void) {
    return g_status;
}

long magnistra_profile_media_tls_verify_result(void) {
    return g_verify;
}

long long magnistra_profile_media_body_length(void) {
    return (long long)g_body.size;
}

const unsigned char *magnistra_profile_media_body(void) {
    return g_body.data;
}

int magnistra_profile_graphql_media_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *user_id,
    const char *username,
    const char *max_id,
    int by_username
) {
    CURL *easy = NULL;
    CURLcode rc;
    struct curl_slist *headers = NULL;

    char device_uuid[64];
    char family_uuid[64];
    char android_id[64];

    char language_header[512];
    char csrf_header[1024];
    char device_header[128];
    char family_header[128];
    char android_header[128];

    char mid_value[1024];
    char mid_header[1200];

    char variables[12288];
    char *escaped_variables = NULL;
    char *post_body = NULL;
    size_t post_body_size = 0;

    (void)user_agent;
    (void)username;
    (void)by_username;

    reset_state();

    if (
        !ca_path ||
        !ca_path[0] ||
        !cookie_header ||
        !cookie_header[0] ||
        !csrf_token ||
        !csrf_token[0] ||
        !user_id ||
        !user_id[0]
    ) {
        return -7100;
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
        return -7101;
    }

    device_values(
        user_id,
        device_uuid,
        sizeof(device_uuid),
        family_uuid,
        sizeof(family_uuid),
        android_id,
        sizeof(android_id)
    );

    snprintf(
        language_header,
        sizeof(language_header),
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

    snprintf(
        device_header,
        sizeof(device_header),
        "X-IG-Device-ID: %s",
        device_uuid
    );

    snprintf(
        family_header,
        sizeof(family_header),
        "X-IG-Family-Device-ID: %s",
        family_uuid
    );

    snprintf(
        android_header,
        sizeof(android_header),
        "X-IG-Android-ID: %s",
        android_id
    );

    if (
        max_id &&
        max_id[0]
    ) {
        snprintf(
            variables,
            sizeof(variables),
            "{"
            "\"request_media_chunk\":true,"
            "\"skip_clips_captions_fields\":false,"
            "\"fetch_profile_grid_items\":true,"
            "\"exclude_comment\":\"false\","
            "\"request_hints_chunk\":false,"
            "\"include_unseen_media_ids\":false,"
            "\"exclude_pinned_posts\":false,"
            "\"enable_carousel_media_count_in_deferred\":true,"
            "\"include_fb_mentioned_users\":false,"
            "\"include_attribution_ui_data\":true,"
            "\"include_profile_grid_rendering_option\":false,"
            "\"count\":9,"
            "\"initial_count_carousel_media\":5,"
            "\"exclude_collaborative_posts\":false,"
            "\"include_is_photo_comments_composer_enabled_for_author\":false,"
            "\"include_associated_highlights\":false,"
            "\"include_attribution_ui_data_v2\":true,"
            "\"include_media_notes_fields\":true,"
            "\"include_eligible_insights_entrypoints\":false,"
            "\"include_accessibility_caption_for_carousel\":true,"
            "\"defer_maybe_non_essential_lightweight_fields\":false,"
            "\"num_previews_for_associated_highlights\":3,"
            "\"include_videos_for_associated_highlights\":false,"
            "\"exclude_user\":false,"
            "\"defer_hints_chunk\":false,"
            "\"exclude_highlights\":true,"
            "\"include_ring_creator_fields\":false,"
            "\"include_timeline_ordered_edge\":false,"
            "\"user_id\":\"%s\","
            "\"max_id\":\"%s\","
            "\"exclude_besties_content\":true,"
            "\"force_compute_user_tags\":false,"
            "\"enable_profile_fm_integration\":false,"
            "\"include_is_unseen_by_viewer\":false"
            "}",
            user_id,
            max_id
        );
    } else {
        snprintf(
            variables,
            sizeof(variables),
            "{"
            "\"request_media_chunk\":true,"
            "\"skip_clips_captions_fields\":false,"
            "\"fetch_profile_grid_items\":true,"
            "\"exclude_comment\":\"false\","
            "\"request_hints_chunk\":false,"
            "\"include_unseen_media_ids\":false,"
            "\"exclude_pinned_posts\":false,"
            "\"enable_carousel_media_count_in_deferred\":true,"
            "\"include_fb_mentioned_users\":false,"
            "\"include_attribution_ui_data\":true,"
            "\"include_profile_grid_rendering_option\":false,"
            "\"count\":9,"
            "\"initial_count_carousel_media\":5,"
            "\"exclude_collaborative_posts\":false,"
            "\"include_is_photo_comments_composer_enabled_for_author\":false,"
            "\"include_associated_highlights\":false,"
            "\"include_attribution_ui_data_v2\":true,"
            "\"include_media_notes_fields\":true,"
            "\"include_eligible_insights_entrypoints\":false,"
            "\"include_accessibility_caption_for_carousel\":true,"
            "\"defer_maybe_non_essential_lightweight_fields\":false,"
            "\"num_previews_for_associated_highlights\":3,"
            "\"include_videos_for_associated_highlights\":false,"
            "\"exclude_user\":false,"
            "\"defer_hints_chunk\":false,"
            "\"exclude_highlights\":true,"
            "\"include_ring_creator_fields\":false,"
            "\"include_timeline_ordered_edge\":false,"
            "\"user_id\":\"%s\","
            "\"exclude_besties_content\":true,"
            "\"force_compute_user_tags\":false,"
            "\"enable_profile_fm_integration\":false,"
            "\"include_is_unseen_by_viewer\":false"
            "}",
            user_id
        );
    }

    escaped_variables =
        curl_easy_escape(
            easy,
            variables,
            0
        );

    if (!escaped_variables) {
        curl_easy_cleanup(
            easy
        );

        curl_global_cleanup();

        return -7102;
    }

    post_body_size =
        strlen(
            escaped_variables
        ) +
        1024;

    post_body =
        (char *)
            malloc(
                post_body_size
            );

    if (!post_body) {
        curl_free(
            escaped_variables
        );

        curl_easy_cleanup(
            easy
        );

        curl_global_cleanup();

        return -7103;
    }

    snprintf(
        post_body,
        post_body_size,
        "method=post"
        "&pretty=false"
        "&format=json"
        "&server_timestamps=true"
        "&locale=en_US"
        "&fb_api_req_friendly_name=IGProfileTimelineQuery"
        "&fb_api_caller_class=graphservice"
        "&client_doc_id=56030350814417327502004290437"
        "&variables=%s",
        escaped_variables
    );

    headers =
        curl_slist_append(
            headers,
            "Accept: */*"
        );

    headers =
        curl_slist_append(
            headers,
            language_header
        );

    headers =
        curl_slist_append(
            headers,
            csrf_header
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-App-ID: 567067343352427"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-App-Locale: en_US"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-Device-Locale: en_US"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-Mapped-Locale: en_US"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-Connection-Type: WIFI"
        );

    headers =
        curl_slist_append(
            headers,
            "X-IG-Timezone-Offset: 7200"
        );

    headers =
        curl_slist_append(
            headers,
            "X-Bloks-Version-Id: 935a519904e9017324cdedb64a283a3c2c1a3d5b0bbc698b451f5aef72cc11df"
        );

    headers =
        curl_slist_append(
            headers,
            device_header
        );

    headers =
        curl_slist_append(
            headers,
            family_header
        );

    headers =
        curl_slist_append(
            headers,
            android_header
        );

    headers =
        curl_slist_append(
            headers,
            "Content-Type: application/x-www-form-urlencoded"
        );

    headers =
        curl_slist_append(
            headers,
            "X-FB-Friendly-Name: IGProfileTimelineQuery"
        );

    if (
        cookie_value(
            cookie_header,
            "mid",
            mid_value,
            sizeof(mid_value)
        )
    ) {
        snprintf(
            mid_header,
            sizeof(mid_header),
            "X-MID: %s",
            mid_value
        );

        headers =
            curl_slist_append(
                headers,
                mid_header
            );
    }

    curl_easy_setopt(
        easy,
        CURLOPT_URL,
        "https://i.instagram.com/graphql/query"
    );

    curl_easy_setopt(
        easy,
        CURLOPT_USERAGENT,
        k_mobile_ua
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
        CURLOPT_HTTP_CONTENT_DECODING,
        1L
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
        CURLOPT_POST,
        1L
    );

    curl_easy_setopt(
        easy,
        CURLOPT_POSTFIELDS,
        post_body
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

    curl_free(
        escaped_variables
    );

    free(
        post_body
    );

    curl_slist_free_all(
        headers
    );

    curl_easy_cleanup(
        easy
    );

    curl_global_cleanup();

    return (int)rc;
}
