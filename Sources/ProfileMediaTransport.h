#ifndef MAGNISTRA_PROFILE_MEDIA_TRANSPORT_H
#define MAGNISTRA_PROFILE_MEDIA_TRANSPORT_H

#ifdef __cplusplus
extern "C" {
#endif

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
);

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
);

long magnistra_profile_media_http_status(void);
long magnistra_profile_media_tls_verify_result(void);
long long magnistra_profile_media_body_length(void);
const unsigned char *magnistra_profile_media_body(void);

#ifdef __cplusplus
}
#endif

#include "ExploreTransport.h"

#endif
