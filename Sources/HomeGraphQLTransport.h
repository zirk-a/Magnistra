#ifndef MAGNISTRA_HOME_GRAPHQL_TRANSPORT_H
#define MAGNISTRA_HOME_GRAPHQL_TRANSPORT_H
#ifdef __cplusplus
extern "C" {
#endif
int magnistra_home_graphql_fetch(const char *ca_path,const char *user_agent,
    const char *language,const char *cookies,const char *csrf,const char *variables_json);
int magnistra_home_graphql_stage(void);
unsigned long magnistra_home_graphql_ctx_flags(void);
long magnistra_home_graphql_bootstrap_status(void);
long long magnistra_home_graphql_bootstrap_bytes(void);
long long magnistra_home_graphql_post_bytes(void);
int magnistra_home_graphql_cookie_seeded(void);
int magnistra_home_graphql_cookie_after_get(void);
int magnistra_home_graphql_cookie_csrf_changed(void);
int magnistra_home_graphql_cookie_seed_failed(void);
long magnistra_home_graphql_http_status(void);
long magnistra_home_graphql_tls_verify_result(void);
const unsigned char *magnistra_home_graphql_body(void);
long long magnistra_home_graphql_body_length(void);
int magnistra_home_graphql_browser_header_flags(void);
#ifdef __cplusplus
}
#endif
#endif
