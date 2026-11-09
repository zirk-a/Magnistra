#ifndef MAGNISTRA_REELS_TRANSPORT_H
#define MAGNISTRA_REELS_TRANSPORT_H

#ifdef __cplusplus
extern "C" {
#endif

int magnistra_reels_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookie_header,
    const char *csrf_token,
    const char *max_id
);

long magnistra_reels_http_status(void);
long magnistra_reels_tls_verify_result(void);
long long magnistra_reels_body_length(void);
const unsigned char *magnistra_reels_body(void);

#ifdef __cplusplus
}
#endif

#endif
