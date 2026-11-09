#include "ActivityTransport.h"

#include <curl/curl.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

static unsigned char *g_body = NULL;
static size_t g_body_len = 0;
static long g_http_status = 0;
static long g_tls_verify_result = 0;

static void magnistra_activity_clear_body(void)
{
    if (g_body != NULL) {
        free(g_body);
        g_body = NULL;
    }

    g_body_len = 0;
    g_http_status = 0;
    g_tls_verify_result = 0;
}

static size_t magnistra_activity_write(
    char *ptr,
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
        g_body,
        g_body_len + incoming + 1
    );

    if (next == NULL) {
        return 0;
    }

    g_body = next;

    memcpy(
        g_body + g_body_len,
        ptr,
        incoming
    );

    g_body_len += incoming;
    g_body[g_body_len] = 0;

    return incoming;
}

static struct curl_slist *magnistra_activity_headers(
    const char *language,
    const char *csrf_token
)
{
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

    return headers;
}

static CURLcode magnistra_activity_perform(
    const char *url,
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token
)
{
    CURL *curl = NULL;
    CURLcode code = CURLE_FAILED_INIT;
    struct curl_slist *headers = NULL;

    magnistra_activity_clear_body();

    curl = curl_easy_init();

    if (curl == NULL) {
        return CURLE_FAILED_INIT;
    }

    headers = magnistra_activity_headers(
        language,
        csrf_token
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
        CURLOPT_WRITEFUNCTION,
        magnistra_activity_write
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

    if (ca_path != NULL && ca_path[0] != 0) {
        curl_easy_setopt(
            curl,
            CURLOPT_CAINFO,
            ca_path
        );
    }

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
        &g_http_status
    );

    curl_easy_getinfo(
        curl,
        CURLINFO_SSL_VERIFYRESULT,
        &g_tls_verify_result
    );

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return code;
}

static int magnistra_activity_body_looks_json(void)
{
    size_t i = 0;

    if (g_body == NULL || g_body_len == 0) {
        return 0;
    }

    while (i < g_body_len) {
        unsigned char c = g_body[i];

        if (
            c == ' ' ||
            c == '\t' ||
            c == '\r' ||
            c == '\n'
        ) {
            i++;
            continue;
        }

        return c == '{' || c == '[';
    }

    return 0;
}

static int magnistra_activity_copy_between(
    const char *source,
    const char *prefix,
    const char *suffix,
    char *output,
    size_t output_size
)
{
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

static int magnistra_activity_extract_fb_dtsg(
    const char *html,
    char *output,
    size_t output_size
)
{
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
            magnistra_activity_copy_between(
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

static int magnistra_activity_extract_jazoest(
    const char *html,
    char *output,
    size_t output_size
)
{
    if (
        magnistra_activity_copy_between(
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
        magnistra_activity_copy_between(
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

static int magnistra_activity_derive_jazoest(
    const char *fb_dtsg,
    char *output,
    size_t output_size
)
{
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

static CURLcode magnistra_activity_perform_post(
    const char *url,
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *fb_dtsg,
    const char *jazoest
)
{
    CURL *curl = NULL;
    CURLcode code = CURLE_FAILED_INIT;
    struct curl_slist *headers = NULL;
    char *escaped_dtsg = NULL;
    char *escaped_jazoest = NULL;
    char *post_fields = NULL;
    size_t post_size;

    magnistra_activity_clear_body();

    curl = curl_easy_init();

    if (curl == NULL) {
        return CURLE_FAILED_INIT;
    }

    headers =
        magnistra_activity_headers(
            language,
            csrf_token
        );

    headers = curl_slist_append(
        headers,
        "Content-Type: application/x-www-form-urlencoded"
    );

    headers = curl_slist_append(
        headers,
        "Origin: https://www.instagram.com"
    );

    escaped_dtsg =
        curl_easy_escape(
            curl,
            fb_dtsg,
            0
        );

    escaped_jazoest =
        curl_easy_escape(
            curl,
            jazoest,
            0
        );

    if (
        escaped_dtsg == NULL ||
        escaped_jazoest == NULL
    ) {
        if (escaped_dtsg != NULL) {
            curl_free(escaped_dtsg);
        }

        if (escaped_jazoest != NULL) {
            curl_free(escaped_jazoest);
        }

        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);

        return CURLE_OUT_OF_MEMORY;
    }

    post_size =
        strlen(escaped_dtsg) +
        strlen(escaped_jazoest) +
        32;

    post_fields =
        (char *)malloc(post_size);

    if (post_fields == NULL) {
        curl_free(escaped_dtsg);
        curl_free(escaped_jazoest);
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);

        return CURLE_OUT_OF_MEMORY;
    }

    snprintf(
        post_fields,
        post_size,
        "fb_dtsg=%s&jazoest=%s",
        escaped_dtsg,
        escaped_jazoest
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
        CURLOPT_WRITEFUNCTION,
        magnistra_activity_write
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

    if (ca_path != NULL && ca_path[0] != 0) {
        curl_easy_setopt(
            curl,
            CURLOPT_CAINFO,
            ca_path
        );
    }

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
        &g_http_status
    );

    curl_easy_getinfo(
        curl,
        CURLINFO_SSL_VERIFYRESULT,
        &g_tls_verify_result
    );

    free(post_fields);
    curl_free(escaped_dtsg);
    curl_free(escaped_jazoest);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return code;
}

static CURLcode magnistra_activity_perform_post_root(
    const char *shortcode,
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *fb_dtsg,
    const char *jazoest
)
{
    CURL *curl = NULL;
    CURLcode code = CURLE_FAILED_INIT;
    struct curl_slist *headers = NULL;
    char variables[4096];
    char *escaped_dtsg = NULL;
    char *escaped_jazoest = NULL;
    char *escaped_variables = NULL;
    char *post_fields = NULL;
    size_t post_size;

    if (
        shortcode == NULL ||
        shortcode[0] == 0
    ) {
        return CURLE_URL_MALFORMAT;
    }

    magnistra_activity_clear_body();

    curl = curl_easy_init();

    if (curl == NULL) {
        return CURLE_FAILED_INIT;
    }

    headers =
        magnistra_activity_headers(
            language,
            csrf_token
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
        "X-FB-Friendly-Name: PolarisPostRootQuery"
    );

    snprintf(
        variables,
        sizeof(variables),
        "{"
        "\"shortcode\":\"%s\","
        "\"__relay_internal__pv__PolarisAIGMMediaWebLabelEnabledrelayprovider\":false"
        "}",
        shortcode
    );

    escaped_dtsg =
        curl_easy_escape(
            curl,
            fb_dtsg,
            0
        );

    escaped_jazoest =
        curl_easy_escape(
            curl,
            jazoest,
            0
        );

    escaped_variables =
        curl_easy_escape(
            curl,
            variables,
            0
        );

    if (
        escaped_dtsg == NULL ||
        escaped_jazoest == NULL ||
        escaped_variables == NULL
    ) {
        if (escaped_dtsg != NULL) {
            curl_free(escaped_dtsg);
        }

        if (escaped_jazoest != NULL) {
            curl_free(escaped_jazoest);
        }

        if (escaped_variables != NULL) {
            curl_free(escaped_variables);
        }

        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);

        return CURLE_OUT_OF_MEMORY;
    }

    post_size =
        strlen(escaped_dtsg) +
        strlen(escaped_jazoest) +
        strlen(escaped_variables) +
        256;

    post_fields =
        (char *)malloc(post_size);

    if (post_fields == NULL) {
        curl_free(escaped_dtsg);
        curl_free(escaped_jazoest);
        curl_free(escaped_variables);
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
        "&doc_id=27128499623469141"
        "&fb_api_caller_class=RelayModern"
        "&fb_api_req_friendly_name=PolarisPostRootQuery"
        "&server_timestamps=true",
        escaped_dtsg,
        escaped_jazoest,
        escaped_variables
    );

    curl_easy_setopt(
        curl,
        CURLOPT_URL,
        "https://www.instagram.com/graphql/query"
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
        CURLOPT_WRITEFUNCTION,
        magnistra_activity_write
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

    if (ca_path != NULL && ca_path[0] != 0) {
        curl_easy_setopt(
            curl,
            CURLOPT_CAINFO,
            ca_path
        );
    }

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
        &g_http_status
    );

    curl_easy_getinfo(
        curl,
        CURLINFO_SSL_VERIFYRESULT,
        &g_tls_verify_result
    );

    free(post_fields);
    curl_free(escaped_dtsg);
    curl_free(escaped_jazoest);
    curl_free(escaped_variables);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return code;
}

int magnistra_activity_fetch_post_root(
    const char *shortcode,
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token
)
{
    CURLcode code;
    char fb_dtsg[1024];
    char jazoest[2048];
    int jazoest_ok = 0;

    if (
        shortcode == NULL ||
        shortcode[0] == 0
    ) {
        return (int)CURLE_URL_MALFORMAT;
    }

    fb_dtsg[0] = 0;
    jazoest[0] = 0;

    code =
        magnistra_activity_perform(
            "https://www.instagram.com/",
            ca_path,
            user_agent,
            language,
            cookies,
            csrf_token
        );

    if (
        code != CURLE_OK ||
        g_http_status < 200 ||
        g_http_status >= 300 ||
        g_body == NULL ||
        g_body_len == 0
    ) {
        return (int)code;
    }

    if (
        !magnistra_activity_extract_fb_dtsg(
            (const char *)g_body,
            fb_dtsg,
            sizeof(fb_dtsg)
        )
    ) {
        g_http_status = 462;
        return (int)CURLE_GOT_NOTHING;
    }

    jazoest_ok =
        magnistra_activity_extract_jazoest(
            (const char *)g_body,
            jazoest,
            sizeof(jazoest)
        );

    if (!jazoest_ok) {
        jazoest_ok =
            magnistra_activity_derive_jazoest(
                fb_dtsg,
                jazoest,
                sizeof(jazoest)
            );
    }

    if (!jazoest_ok) {
        g_http_status = 463;
        return (int)CURLE_GOT_NOTHING;
    }

    code =
        magnistra_activity_perform_post_root(
            shortcode,
            ca_path,
            user_agent,
            language,
            cookies,
            csrf_token,
            fb_dtsg,
            jazoest
        );

    memset(
        fb_dtsg,
        0,
        sizeof(fb_dtsg)
    );

    memset(
        jazoest,
        0,
        sizeof(jazoest)
    );

    if (
        code == CURLE_OK &&
        g_http_status >= 200 &&
        g_http_status < 300 &&
        magnistra_activity_body_looks_json()
    ) {
        return 0;
    }

    if (code == CURLE_OK) {
        return (int)CURLE_GOT_NOTHING;
    }

    return (int)code;
}

int magnistra_activity_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token
)
{
    CURLcode code;
    char fb_dtsg[1024];
    char jazoest[2048];
    int jazoest_ok = 0;

    fb_dtsg[0] = 0;
    jazoest[0] = 0;

    code =
        magnistra_activity_perform(
            "https://www.instagram.com/",
            ca_path,
            user_agent,
            language,
            cookies,
            csrf_token
        );

    if (
        code != CURLE_OK ||
        g_http_status < 200 ||
        g_http_status >= 300 ||
        g_body == NULL ||
        g_body_len == 0
    ) {
        return (int)code;
    }

    if (
        !magnistra_activity_extract_fb_dtsg(
            (const char *)g_body,
            fb_dtsg,
            sizeof(fb_dtsg)
        )
    ) {
        g_http_status = 460;
        return (int)CURLE_GOT_NOTHING;
    }

    jazoest_ok =
        magnistra_activity_extract_jazoest(
            (const char *)g_body,
            jazoest,
            sizeof(jazoest)
        );

    if (!jazoest_ok) {
        jazoest_ok =
            magnistra_activity_derive_jazoest(
                fb_dtsg,
                jazoest,
                sizeof(jazoest)
            );
    }

    if (!jazoest_ok) {
        g_http_status = 461;
        return (int)CURLE_GOT_NOTHING;
    }

    code =
        magnistra_activity_perform_post(
            "https://www.instagram.com/api/v1/news/inbox/",
            ca_path,
            user_agent,
            language,
            cookies,
            csrf_token,
            fb_dtsg,
            jazoest
        );

    memset(
        fb_dtsg,
        0,
        sizeof(fb_dtsg)
    );

    memset(
        jazoest,
        0,
        sizeof(jazoest)
    );

    if (
        code == CURLE_OK &&
        g_http_status >= 200 &&
        g_http_status < 300 &&
        magnistra_activity_body_looks_json()
    ) {
        return 0;
    }

    return (int)code;
}

long magnistra_activity_http_status(void)
{
    return g_http_status;
}

long magnistra_activity_tls_verify_result(void)
{
    return g_tls_verify_result;
}

const unsigned char *magnistra_activity_body(void)
{
    return g_body;
}

size_t magnistra_activity_body_length(void)
{
    return g_body_len;
}
