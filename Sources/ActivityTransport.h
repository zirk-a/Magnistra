#ifndef MAGNISTRA_ACTIVITY_TRANSPORT_H
#define MAGNISTRA_ACTIVITY_TRANSPORT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int magnistra_activity_fetch(
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token
);

int magnistra_activity_fetch_post_root(
    const char *shortcode,
    const char *ca_path,
    const char *user_agent,
    const char *language,
    const char *cookies,
    const char *csrf_token
);

long magnistra_activity_http_status(void);
long magnistra_activity_tls_verify_result(void);
const unsigned char *magnistra_activity_body(void);
size_t magnistra_activity_body_length(void);

#ifdef __cplusplus
}
#endif

#endif
