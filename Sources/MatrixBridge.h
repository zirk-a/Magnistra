#ifndef magnistra_matrix_curl_h
#define magnistra_matrix_curl_h

#include <stddef.h>

typedef void *MagnistraMatrixCurlHandle;

typedef size_t (*CurlBridgeWriteFn)(const void *ptr, size_t size, size_t nmemb, void *userdata);

typedef int (*CurlBridgeProgressFn)(void *clientp,
                                    long long dltotal, long long dlnow,
                                    long long ultotal, long long ulnow);

void        magnistra_matrix_curl_global_init(void);
MagnistraMatrixCurlHandle  magnistra_matrix_curl_init(void);
void        magnistra_matrix_curl_cleanup(MagnistraMatrixCurlHandle h);
void        magnistra_matrix_curl_set_url(MagnistraMatrixCurlHandle h, const char *url);
void        magnistra_matrix_curl_set_ssl_verify(MagnistraMatrixCurlHandle h);
void        magnistra_matrix_curl_set_ca_bundle(MagnistraMatrixCurlHandle h, const char *path);
void        magnistra_matrix_curl_set_follow_redirects(MagnistraMatrixCurlHandle h);
void        magnistra_matrix_curl_set_timeout(MagnistraMatrixCurlHandle h, long secs);

void        magnistra_matrix_curl_set_low_speed_abort(MagnistraMatrixCurlHandle h, long bytes_per_sec, long secs);
void        magnistra_matrix_curl_set_write_fn(MagnistraMatrixCurlHandle h, CurlBridgeWriteFn fn, void *userdata);
void        magnistra_matrix_curl_set_progress_fn(MagnistraMatrixCurlHandle h, CurlBridgeProgressFn fn, void *clientp);

void        magnistra_matrix_curl_set_post_body(MagnistraMatrixCurlHandle h, const void *body, long len);
void        magnistra_matrix_curl_set_put_body(MagnistraMatrixCurlHandle h, const void *body, long len);

void       *magnistra_matrix_curl_upload_open(const char *path);
void        magnistra_matrix_curl_upload_close(void *file);
void        magnistra_matrix_curl_set_post_stream(MagnistraMatrixCurlHandle h, void *file, long long len);
void       *magnistra_matrix_curl_headers_append(void *list, const char *header);
void        magnistra_matrix_curl_set_headers(MagnistraMatrixCurlHandle h, void *list);
void        magnistra_matrix_curl_headers_free(void *list);

int         magnistra_matrix_curl_perform(MagnistraMatrixCurlHandle h);
long        magnistra_matrix_curl_response_code(MagnistraMatrixCurlHandle h);
const char *magnistra_matrix_curl_strerror(int code);

#endif

#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
int magnistra_matrix_crypto_ed25519_keygen(uint8_t *priv32, uint8_t *pub32);
int magnistra_matrix_crypto_ed25519_sign(const uint8_t *priv32, const uint8_t *msg, size_t msglen, uint8_t *sig64);
int magnistra_matrix_crypto_x25519_keygen(uint8_t *priv32, uint8_t *pub32);
int magnistra_matrix_crypto_x25519_shared(const uint8_t *priv32, const uint8_t *peer32, uint8_t *out32);
int magnistra_matrix_crypto_sha256(const uint8_t *data, size_t len, uint8_t *out32);
int magnistra_matrix_crypto_hmac_sha256(const uint8_t *key, size_t keylen, const uint8_t *data, size_t datalen, uint8_t *out32);
int magnistra_matrix_crypto_hkdf_sha256(const uint8_t *ikm, size_t ikmlen,
                                  const uint8_t *info, size_t infolen,
                                  uint8_t *out, size_t outlen);
#ifdef __cplusplus
}
#endif

int magnistra_matrix_crypto_ed25519_verify(const uint8_t *pub32,
                                     const uint8_t *msg, size_t msglen,
                                     const uint8_t *sig64);
int magnistra_matrix_crypto_aes256_cbc_decrypt(const uint8_t *key32,
                                         const uint8_t *iv16,
                                         const uint8_t *in, size_t inlen,
                                         uint8_t *out, size_t *outlen);
int magnistra_matrix_crypto_constant_equal(const uint8_t *a, const uint8_t *b,
                                     size_t len);

int magnistra_matrix_crypto_random_bytes(uint8_t *out, size_t len);
int magnistra_matrix_crypto_aes256_cbc_encrypt(const uint8_t *key32,
                                         const uint8_t *iv16,
                                         const uint8_t *in, size_t inlen,
                                         uint8_t *out, size_t *outlen);
int magnistra_matrix_crypto_aes256_ctr_encrypt_file(const char *input_path,
                                              const char *output_path,
                                              const uint8_t *key32,
                                              const uint8_t *iv16,
                                              uint8_t *sha256_out32);
int magnistra_matrix_crypto_aes256_ctr_decrypt_file(const char *input_path,
                                              const char *output_path,
                                              const uint8_t *key32,
                                              const uint8_t *iv16,
                                              const uint8_t *sha256_expected32);

#ifdef __cplusplus
extern "C" {
#endif
int magnistra_matrix_audio_set_default_speaker(int enabled);
#ifdef __cplusplus
}
#endif
