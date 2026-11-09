/* Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md. */
#include "MatrixBridge.h"
#include <curl/curl.h>
#include <stdio.h>

void magnistra_matrix_curl_global_init(void) {
    curl_global_init(CURL_GLOBAL_ALL);
}

MagnistraMatrixCurlHandle magnistra_matrix_curl_init(void) {
    return curl_easy_init();
}

void magnistra_matrix_curl_cleanup(MagnistraMatrixCurlHandle h) {
    curl_easy_cleanup(h);
}

void magnistra_matrix_curl_set_url(MagnistraMatrixCurlHandle h, const char *url) {
    curl_easy_setopt(h, CURLOPT_URL, url);
}

void magnistra_matrix_curl_set_ssl_verify(MagnistraMatrixCurlHandle h) {
    curl_easy_setopt(h, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(h, CURLOPT_SSL_VERIFYHOST, 2L);
}

void magnistra_matrix_curl_set_ca_bundle(MagnistraMatrixCurlHandle h, const char *path) {
    if (path) {
        curl_easy_setopt(h, CURLOPT_CAINFO, path);
    }
}

void magnistra_matrix_curl_set_follow_redirects(MagnistraMatrixCurlHandle h) {
    curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(h, CURLOPT_MAXREDIRS, 10L);
}

void magnistra_matrix_curl_set_timeout(MagnistraMatrixCurlHandle h, long secs) {
    curl_easy_setopt(h, CURLOPT_TIMEOUT, secs);
}

void magnistra_matrix_curl_set_low_speed_abort(MagnistraMatrixCurlHandle h, long bytes_per_sec, long secs) {
    curl_easy_setopt(h, CURLOPT_LOW_SPEED_LIMIT, bytes_per_sec);
    curl_easy_setopt(h, CURLOPT_LOW_SPEED_TIME, secs);
}

void magnistra_matrix_curl_set_write_fn(MagnistraMatrixCurlHandle h, CurlBridgeWriteFn fn, void *userdata) {
    curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, fn);
    curl_easy_setopt(h, CURLOPT_WRITEDATA, userdata);
}

void magnistra_matrix_curl_set_progress_fn(MagnistraMatrixCurlHandle h, CurlBridgeProgressFn fn, void *clientp) {
    curl_easy_setopt(h, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(h, CURLOPT_XFERINFOFUNCTION, fn);
    curl_easy_setopt(h, CURLOPT_XFERINFODATA, clientp);
}

void magnistra_matrix_curl_set_post_body(MagnistraMatrixCurlHandle h, const void *body, long len) {
    curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE, len);
    curl_easy_setopt(h, CURLOPT_COPYPOSTFIELDS, body);
}

void magnistra_matrix_curl_set_put_body(MagnistraMatrixCurlHandle h, const void *body, long len) {
    curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, "PUT");
    curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE, len);
    curl_easy_setopt(h, CURLOPT_COPYPOSTFIELDS, body);
}

static size_t magnistra_matrix_curl_upload_read(char *buffer, size_t size, size_t nitems, void *userdata) {
    return fread(buffer, size, nitems, (FILE *)userdata);
}

void *magnistra_matrix_curl_upload_open(const char *path) {
    return fopen(path, "rb");
}

void magnistra_matrix_curl_upload_close(void *file) {
    if (file) {
        fclose((FILE *)file);
    }
}

void magnistra_matrix_curl_set_post_stream(MagnistraMatrixCurlHandle h, void *file, long long len) {
    curl_easy_setopt(h, CURLOPT_POST, 1L);
    curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)len);
    curl_easy_setopt(h, CURLOPT_READFUNCTION, magnistra_matrix_curl_upload_read);
    curl_easy_setopt(h, CURLOPT_READDATA, file);
}

void *magnistra_matrix_curl_headers_append(void *list, const char *header) {
    return curl_slist_append((struct curl_slist *)list, header);
}

void magnistra_matrix_curl_set_headers(MagnistraMatrixCurlHandle h, void *list) {
    curl_easy_setopt(h, CURLOPT_HTTPHEADER, (struct curl_slist *)list);
}

void magnistra_matrix_curl_headers_free(void *list) {
    curl_slist_free_all((struct curl_slist *)list);
}

int magnistra_matrix_curl_perform(MagnistraMatrixCurlHandle h) {
    return (int)curl_easy_perform(h);
}

long magnistra_matrix_curl_response_code(MagnistraMatrixCurlHandle h) {
    long code = 0;
    curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &code);
    return code;
}

const char *magnistra_matrix_curl_strerror(int code) {
    return curl_easy_strerror((CURLcode)code);
}

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <limits.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/sha.h>
#include <openssl/crypto.h>

int magnistra_matrix_crypto_ed25519_keygen(uint8_t *priv32, uint8_t *pub32) {
    int ok = 0;
    EVP_PKEY_CTX *ctx = NULL;
    EVP_PKEY *key = NULL;
    size_t privlen = 32, publen = 32;
    if (!priv32 || !pub32) return 0;
    ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_ED25519, NULL);
    if (!ctx) goto done;
    if (EVP_PKEY_keygen_init(ctx) <= 0) goto done;
    if (EVP_PKEY_keygen(ctx, &key) <= 0) goto done;
    if (EVP_PKEY_get_raw_private_key(key, priv32, &privlen) <= 0 || privlen != 32) goto done;
    if (EVP_PKEY_get_raw_public_key(key, pub32, &publen) <= 0 || publen != 32) goto done;
    ok = 1;
done:
    EVP_PKEY_free(key);
    EVP_PKEY_CTX_free(ctx);
    return ok;
}

int magnistra_matrix_crypto_ed25519_sign(const uint8_t *priv32, const uint8_t *msg, size_t msglen, uint8_t *sig64) {
    int ok = 0;
    EVP_PKEY *key = NULL;
    EVP_MD_CTX *ctx = NULL;
    size_t siglen = 64;
    if (!priv32 || (!msg && msglen) || !sig64) return 0;
    key = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, priv32, 32);
    if (!key) goto done;
    ctx = EVP_MD_CTX_new();
    if (!ctx) goto done;
    if (EVP_DigestSignInit(ctx, NULL, NULL, NULL, key) <= 0) goto done;
    if (EVP_DigestSign(ctx, sig64, &siglen, msg, msglen) <= 0 || siglen != 64) goto done;
    ok = 1;
done:
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(key);
    return ok;
}

int magnistra_matrix_crypto_x25519_keygen(uint8_t *priv32, uint8_t *pub32) {
    int ok = 0;
    EVP_PKEY_CTX *ctx = NULL;
    EVP_PKEY *key = NULL;
    size_t privlen = 32, publen = 32;
    if (!priv32 || !pub32) return 0;
    ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_X25519, NULL);
    if (!ctx) goto done;
    if (EVP_PKEY_keygen_init(ctx) <= 0) goto done;
    if (EVP_PKEY_keygen(ctx, &key) <= 0) goto done;
    if (EVP_PKEY_get_raw_private_key(key, priv32, &privlen) <= 0 || privlen != 32) goto done;
    if (EVP_PKEY_get_raw_public_key(key, pub32, &publen) <= 0 || publen != 32) goto done;
    ok = 1;
done:
    EVP_PKEY_free(key);
    EVP_PKEY_CTX_free(ctx);
    return ok;
}

int magnistra_matrix_crypto_x25519_shared(const uint8_t *priv32, const uint8_t *peer32, uint8_t *out32) {
    int ok = 0;
    EVP_PKEY *priv = NULL, *peer = NULL;
    EVP_PKEY_CTX *ctx = NULL;
    size_t outlen = 32;
    if (!priv32 || !peer32 || !out32) return 0;
    priv = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, priv32, 32);
    peer = EVP_PKEY_new_raw_public_key(EVP_PKEY_X25519, NULL, peer32, 32);
    if (!priv || !peer) goto done;
    ctx = EVP_PKEY_CTX_new(priv, NULL);
    if (!ctx) goto done;
    if (EVP_PKEY_derive_init(ctx) <= 0) goto done;
    if (EVP_PKEY_derive_set_peer(ctx, peer) <= 0) goto done;
    if (EVP_PKEY_derive(ctx, out32, &outlen) <= 0 || outlen != 32) goto done;
    ok = 1;
done:
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(peer);
    EVP_PKEY_free(priv);
    return ok;
}

int magnistra_matrix_crypto_sha256(const uint8_t *data, size_t len, uint8_t *out32) {
    if ((!data && len) || !out32) return 0;
    return SHA256(data, len, out32) ? 1 : 0;
}

int magnistra_matrix_crypto_hmac_sha256(const uint8_t *key, size_t keylen, const uint8_t *data, size_t datalen, uint8_t *out32) {
    unsigned int outlen = 0;
    if ((!key && keylen) || (!data && datalen) || !out32) return 0;
    if (!HMAC(EVP_sha256(), key, (int)keylen, data, datalen, out32, &outlen)) return 0;
    return outlen == 32 ? 1 : 0;
}

int magnistra_matrix_crypto_hkdf_sha256(const uint8_t *ikm, size_t ikmlen,
                                  const uint8_t *info, size_t infolen,
                                  uint8_t *out, size_t outlen) {
    uint8_t zeros[32] = {0};
    uint8_t prk[32], t[32];
    unsigned int hlen = 0;
    size_t produced = 0, tlen = 0;
    uint8_t counter = 1;
    if ((!ikm && ikmlen) || (!info && infolen) || (!out && outlen)) return 0;
    if (outlen > 255U * 32U) return 0;
    if (!HMAC(EVP_sha256(), zeros, 32, ikm, ikmlen, prk, &hlen) || hlen != 32) return 0;
    while (produced < outlen) {
        size_t buflen = tlen + infolen + 1;
        uint8_t *buf = (uint8_t *)OPENSSL_malloc(buflen ? buflen : 1);
        size_t take;
        if (!buf) { OPENSSL_cleanse(prk, sizeof(prk)); return 0; }
        if (tlen) memcpy(buf, t, tlen);
        if (infolen) memcpy(buf + tlen, info, infolen);
        buf[tlen + infolen] = counter;
        if (!HMAC(EVP_sha256(), prk, 32, buf, buflen, t, &hlen) || hlen != 32) {
            OPENSSL_free(buf); OPENSSL_cleanse(prk, sizeof(prk)); OPENSSL_cleanse(t, sizeof(t)); return 0;
        }
        OPENSSL_free(buf);
        take = outlen - produced;
        if (take > 32) take = 32;
        memcpy(out + produced, t, take);
        produced += take;
        tlen = 32;
        counter++;
    }
    OPENSSL_cleanse(prk, sizeof(prk));
    OPENSSL_cleanse(t, sizeof(t));
    return 1;
}

int magnistra_matrix_crypto_ed25519_verify(const uint8_t *pub32,
                                     const uint8_t *msg, size_t msglen,
                                     const uint8_t *sig64) {
    int ok = 0;
    EVP_PKEY *key = NULL;
    EVP_MD_CTX *ctx = NULL;
    if (!pub32 || (!msg && msglen) || !sig64) return 0;
    key = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, NULL, pub32, 32);
    if (!key) goto done;
    ctx = EVP_MD_CTX_new();
    if (!ctx) goto done;
    if (EVP_DigestVerifyInit(ctx, NULL, NULL, NULL, key) <= 0) goto done;
    ok = EVP_DigestVerify(ctx, sig64, 64, msg, msglen) == 1;
done:
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(key);
    return ok;
}

int magnistra_matrix_crypto_aes256_cbc_decrypt(const uint8_t *key32,
                                         const uint8_t *iv16,
                                         const uint8_t *in, size_t inlen,
                                         uint8_t *out, size_t *outlen) {
    EVP_CIPHER_CTX *ctx = NULL;
    int n1 = 0, n2 = 0, ok = 0;
    size_t cap;
    if (!key32 || !iv16 || (!in && inlen) || !out || !outlen) return 0;
    if (inlen > (size_t)INT_MAX) return 0;
    cap = *outlen;
    if (cap < inlen) return 0;
    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) goto done;
    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, key32, iv16) <= 0) goto done;
    if (EVP_DecryptUpdate(ctx, out, &n1, in, (int)inlen) <= 0) goto done;
    if (EVP_DecryptFinal_ex(ctx, out + n1, &n2) <= 0) goto done;
    if ((size_t)(n1 + n2) > cap) goto done;
    *outlen = (size_t)(n1 + n2);
    ok = 1;
done:
    EVP_CIPHER_CTX_free(ctx);
    return ok;
}

int magnistra_matrix_crypto_constant_equal(const uint8_t *a, const uint8_t *b,
                                     size_t len) {
    if ((!a || !b) && len) return 0;
    return CRYPTO_memcmp(a, b, len) == 0 ? 1 : 0;
}

#include <openssl/rand.h>

int magnistra_matrix_crypto_random_bytes(uint8_t *out, size_t len) {
    if ((!out && len) || len > (size_t)INT_MAX) return 0;
    if (!len) return 1;
    return RAND_bytes(out, (int)len) == 1 ? 1 : 0;
}

int magnistra_matrix_crypto_aes256_cbc_encrypt(const uint8_t *key32,
                                         const uint8_t *iv16,
                                         const uint8_t *in, size_t inlen,
                                         uint8_t *out, size_t *outlen) {
    EVP_CIPHER_CTX *ctx = NULL;
    int n1 = 0, n2 = 0, ok = 0;
    size_t cap;
    if (!key32 || !iv16 || (!in && inlen) || !out || !outlen) return 0;
    if (inlen > (size_t)INT_MAX) return 0;
    cap = *outlen;
    if (cap < inlen + 16) return 0;
    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) goto done;
    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, key32, iv16) <= 0) goto done;
    if (EVP_EncryptUpdate(ctx, out, &n1, in, (int)inlen) <= 0) goto done;
    if (EVP_EncryptFinal_ex(ctx, out + n1, &n2) <= 0) goto done;
    if ((size_t)(n1 + n2) > cap) goto done;
    *outlen = (size_t)(n1 + n2);
    ok = 1;
done:
    EVP_CIPHER_CTX_free(ctx);
    return ok;
}

static int magnistra_matrix_crypto_ctr_file(const char *input_path,
                                      const char *output_path,
                                      const uint8_t *key32,
                                      const uint8_t *iv16,
                                      uint8_t *sha_out,
                                      const uint8_t *sha_expected,
                                      int encrypting) {
    FILE *in_file = NULL;
    FILE *out_file = NULL;
    EVP_CIPHER_CTX *ctx = NULL;
    SHA256_CTX sha_ctx;
    uint8_t in_buf[16384];
    uint8_t out_buf[16384 + EVP_MAX_BLOCK_LENGTH];
    uint8_t digest[32];
    size_t nread;
    int out_len = 0, final_len = 0, ok = 0;

    if (!input_path || !output_path || !key32 || !iv16) return 0;
    if (encrypting && !sha_out) return 0;
    if (!encrypting && !sha_expected) return 0;

    in_file = fopen(input_path, "rb");
    if (!in_file) goto done;
    out_file = fopen(output_path, "wb");
    if (!out_file) goto done;
    if (SHA256_Init(&sha_ctx) != 1) goto done;

    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) goto done;
    if (EVP_CipherInit_ex(ctx, EVP_aes_256_ctr(), NULL, key32, iv16, encrypting ? 1 : 0) <= 0) goto done;

    while ((nread = fread(in_buf, 1, sizeof(in_buf), in_file)) > 0) {
        if (!encrypting && SHA256_Update(&sha_ctx, in_buf, nread) != 1) goto done;
        if (EVP_CipherUpdate(ctx, out_buf, &out_len, in_buf, (int)nread) <= 0) goto done;
        if (encrypting && SHA256_Update(&sha_ctx, out_buf, (size_t)out_len) != 1) goto done;
        if (out_len > 0 &&
            fwrite(out_buf, 1, (size_t)out_len, out_file) != (size_t)out_len) goto done;
    }
    if (ferror(in_file)) goto done;

    if (EVP_CipherFinal_ex(ctx, out_buf, &final_len) <= 0) goto done;
    if (final_len > 0) {
        if (encrypting && SHA256_Update(&sha_ctx, out_buf, (size_t)final_len) != 1) goto done;
        if (fwrite(out_buf, 1, (size_t)final_len, out_file) != (size_t)final_len) goto done;
    }
    if (SHA256_Final(digest, &sha_ctx) != 1) goto done;
    if (encrypting) {
        memcpy(sha_out, digest, 32);
    } else if (CRYPTO_memcmp(digest, sha_expected, 32) != 0) {
        goto done;
    }
    if (fflush(out_file) != 0) goto done;
    ok = 1;

done:
    EVP_CIPHER_CTX_free(ctx);
    if (out_file) fclose(out_file);
    if (in_file) fclose(in_file);
    OPENSSL_cleanse(in_buf, sizeof(in_buf));
    OPENSSL_cleanse(out_buf, sizeof(out_buf));
    OPENSSL_cleanse(digest, sizeof(digest));
    if (!ok && output_path) remove(output_path);
    return ok;
}

int magnistra_matrix_crypto_aes256_ctr_encrypt_file(const char *input_path,
                                              const char *output_path,
                                              const uint8_t *key32,
                                              const uint8_t *iv16,
                                              uint8_t *sha256_out32) {
    return magnistra_matrix_crypto_ctr_file(input_path, output_path, key32, iv16,
                                      sha256_out32, NULL, 1);
}

int magnistra_matrix_crypto_aes256_ctr_decrypt_file(const char *input_path,
                                              const char *output_path,
                                              const uint8_t *key32,
                                              const uint8_t *iv16,
                                              const uint8_t *sha256_expected32) {
    return magnistra_matrix_crypto_ctr_file(input_path, output_path, key32, iv16,
                                      NULL, sha256_expected32, 0);
}

#include <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>

extern int magnistra_curl_process_init_once(void);
#ifdef curl_global_init
#undef curl_global_init
#endif
#ifdef curl_global_cleanup
#undef curl_global_cleanup
#endif
#define curl_global_init(...) ((CURLcode)magnistra_curl_process_init_once())
#define curl_global_cleanup() ((void)0)

int magnistra_matrix_audio_set_default_speaker(int enabled) {
    typedef OSStatus (*MagnistraMatrixAudioSessionSetPropertyFn)(
        AudioSessionPropertyID, UInt32, const void *);
    MagnistraMatrixAudioSessionSetPropertyFn fn =
        (MagnistraMatrixAudioSessionSetPropertyFn)dlsym(RTLD_DEFAULT, "AudioSessionSetProperty");
    if (!fn) return -1;

    UInt32 value = enabled ? 1u : 0u;
    return (int)fn((AudioSessionPropertyID)kAudioSessionProperty_OverrideCategoryDefaultToSpeaker,
                   (UInt32)sizeof(value), &value);
}
