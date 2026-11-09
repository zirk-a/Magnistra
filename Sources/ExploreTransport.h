#ifndef MAGNISTRA_EXPLORE_TRANSPORT_H
#define MAGNISTRA_EXPLORE_TRANSPORT_H

#ifdef __cplusplus
extern "C" {
#endif

int magnistra_explore_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *max_id
);

int magnistra_explore_graphql_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *variables_json,
    const char *doc_id,
    const char *friendly_name
);

int magnistra_explore_wbloks_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *app_id,
    const char *request_type,
    const char *params_json
);

long magnistra_explore_search_http_status(void);
long magnistra_explore_search_tls_verify_result(void);
long long magnistra_explore_search_body_length(void);
const unsigned char *magnistra_explore_search_body(void);

int magnistra_explore_rest_get(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token,
    const char *url
);

long magnistra_explore_http_status(void);
long magnistra_explore_tls_verify_result(void);
long long magnistra_explore_body_length(void);
const unsigned char *magnistra_explore_body(void);

#ifdef __cplusplus
}
#endif

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
);

long magnistra_direct_media_http_status(void);
long magnistra_direct_media_tls_verify_result(void);
long long magnistra_direct_media_body_length(void);
const unsigned char *magnistra_direct_media_body(void);

#endif
