#ifndef MAGNISTRA_TRANSPORT_H
#define MAGNISTRA_TRANSPORT_H

#ifdef __cplusplus
extern "C" {
#endif

int magnistra_transport_fetch_feed(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *max_id,
    const char *pagination_json
);

int magnistra_transport_fetch_user_info(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *user_id
);

int magnistra_transport_fetch_comments(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *media_id,
    const char *max_id
);

int magnistra_transport_fetch_public_image(
    const char *ca_path,
    const char *user_agent,
    const char *image_url
);

long magnistra_transport_http_status(void);
long magnistra_transport_tls_verify_result(void);
long long magnistra_transport_body_length(void);
const char *magnistra_transport_content_type(void);
const char *magnistra_transport_tls_backend(void);
const char *magnistra_transport_error(void);
const unsigned char *magnistra_transport_body(void);

#ifdef __cplusplus
}
#endif

int magnistra_matrix_login_post_json(
    const char *ca_path,
    const char *url,
    const char *user_agent,
    const char *json_body
);
long magnistra_matrix_login_http_status(void);
long magnistra_matrix_login_tls_verify_result(void);
long long magnistra_matrix_login_body_length(void);
const unsigned char *magnistra_matrix_login_body(void);

int magnistra_matrix_space_get_json(
    const char *ca_path,
    const char *url,
    const char *access_token,
    const char *user_agent
);
long magnistra_matrix_space_http_status(void);
long magnistra_matrix_space_tls_verify_result(void);
long long magnistra_matrix_space_body_length(void);
const unsigned char *magnistra_matrix_space_body(void);

int magnistra_transport_post_action_request(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *relative_path,
    const char *post_body,
    int use_post
);

#endif
