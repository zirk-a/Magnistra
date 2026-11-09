#ifndef magnistra_recovery_crypto_bridge_h
#define magnistra_recovery_crypto_bridge_h

#include <stdint.h>
#include <stddef.h>

int magnistra_recovery_crypto_sha256(const uint8_t *data, size_t len, uint8_t *out32);

int magnistra_recovery_crypto_hmac_sha256(const uint8_t *key, size_t key_len,
                       const uint8_t *data, size_t data_len,
                       uint8_t *out32);

int magnistra_recovery_crypto_hkdf_sha256(const uint8_t *ikm, size_t ikm_len,
                       const uint8_t *salt, size_t salt_len,
                       const uint8_t *info, size_t info_len,
                       uint8_t *out, size_t out_len);

int magnistra_recovery_crypto_aes256_ctr(const uint8_t *key32, const uint8_t *iv16,
                      const uint8_t *in, size_t len, uint8_t *out);

int magnistra_recovery_crypto_aes256_cbc_decrypt(const uint8_t *key32, const uint8_t *iv16,
                              const uint8_t *in, size_t len,
                              uint8_t *out, size_t *out_len);

int magnistra_recovery_crypto_x25519(const uint8_t *private32, const uint8_t *peer_public32,
                  uint8_t *out_shared32);

int magnistra_recovery_crypto_x25519_public(const uint8_t *private32, uint8_t *out_public32);

int magnistra_recovery_crypto_ed25519_verify(const uint8_t *public32,
                          const uint8_t *msg, size_t msg_len,
                          const uint8_t *sig64);

#endif
