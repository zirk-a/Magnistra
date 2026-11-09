#include <stddef.h>
#include <stdint.h>
#include <string.h>

extern int sodium_init(void);
extern void randombytes_buf(void *buf, size_t size);
extern int crypto_aead_xchacha20poly1305_ietf_encrypt(unsigned char *c,
  unsigned long long *clen, const unsigned char *m, unsigned long long mlen,
  const unsigned char *ad, unsigned long long adlen, const unsigned char *nsec,
  const unsigned char *npub, const unsigned char *k);
extern int crypto_aead_xchacha20poly1305_ietf_decrypt(unsigned char *m,
  unsigned long long *mlen, unsigned char *nsec, const unsigned char *c,
  unsigned long long clen, const unsigned char *ad, unsigned long long adlen,
  const unsigned char *npub, const unsigned char *k);

#define HEADER 28U
#define TAG 16U
#define MAX_PLAINTEXT (32U * 1024U * 1024U)
static const unsigned char magic[4] = {'M','G','V','1'};
static const unsigned char domain[] = "com.zirka.magnistra.matrix.private.v1";

int magnistra_private_seal(const uint8_t *in, size_t n, const uint8_t *key,
                           uint8_t *out, size_t cap, size_t *used) {
    unsigned long long produced = 0;
    if (!in || !key || !out || !used || !n || n > MAX_PLAINTEXT ||
        cap < n + HEADER + TAG || sodium_init() < 0) return -1;
    memcpy(out, magic, 4);
    randombytes_buf(out + 4, 24);
    if (crypto_aead_xchacha20poly1305_ietf_encrypt(out + HEADER, &produced,
            in, (unsigned long long)n, domain, sizeof(domain) - 1,
            NULL, out + 4, key) != 0 || produced != n + TAG) return -2;
    *used = HEADER + (size_t)produced;
    return 0;
}
int magnistra_private_open(const uint8_t *in, size_t n, const uint8_t *key,
                           uint8_t *out, size_t cap, size_t *used) {
    unsigned long long produced = 0;
    if (!in || !key || !out || !used || n <= HEADER + TAG ||
        n > MAX_PLAINTEXT + HEADER + TAG || cap < n - HEADER - TAG ||
        memcmp(in, magic, 4) || sodium_init() < 0) return -1;
    if (crypto_aead_xchacha20poly1305_ietf_decrypt(out, &produced,
            NULL, in + HEADER, (unsigned long long)(n - HEADER),
            domain, sizeof(domain) - 1, in + 4, key) != 0 ||
            produced != n - HEADER - TAG) return -2;
    *used = (size_t)produced;
    return 0;
}
