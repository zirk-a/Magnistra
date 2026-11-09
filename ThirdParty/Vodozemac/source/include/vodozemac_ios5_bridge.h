#ifndef VODOZEMAC_IOS5_BRIDGE_H
#define VODOZEMAC_IOS5_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Version 0x00030000. Opaque handles MUST be released exactly once.
 * Callers MUST serialize access to a given handle on one thread.
 * Invalid dangling pointers are not supported.
 * Data is length-delimited bytes, not NUL-terminated. Returns byte count,
 * or -1 on error / insufficient capacity. Maximum field size: 2 MiB.
 * For Olm inbound use a plaintext buffer at least as long as the Base64 message.
 * Persist encrypted ratchet state ATOMICALLY before transmitting ciphertext.
 * Never roll back restored ratchet state, especially after encryption.
 * Key parameter is exactly 32 random bytes kept securely by host (e.g. Keychain).
 */
typedef void vdz5_handle;
enum { VDZ5_ACCOUNT=1, VDZ5_OLM=2, VDZ5_MEGOLM_OUT=3, VDZ5_MEGOLM_IN=4 };
uint32_t vdz5_r3_abi_version(void);
uint32_t vdz5_r3_bridge_selftest(void); /* bit 0 Olm, bit 1 Megolm */
uint32_t vdz5_r3_ffi_selftest(void); /* 0 = C ABI full roundtrip pass, 4=error */
void vdz5_r3_release(vdz5_handle *handle);
vdz5_handle *vdz5_r3_account_new(void);
ptrdiff_t vdz5_r3_account_identity(vdz5_handle *account,uint32_t which,uint8_t *out,size_t cap); /* 1 Ed25519,2 Curve25519 */
int32_t vdz5_r3_account_generate_otk(vdz5_handle *account,uint32_t n);
ptrdiff_t vdz5_r3_account_unpublished_otk_json(vdz5_handle *account,uint8_t *out,size_t cap);
int32_t vdz5_r3_account_generate_fallback(vdz5_handle *account);
ptrdiff_t vdz5_r3_account_unpublished_fallback_json(vdz5_handle *account,uint8_t *out,size_t cap);
int32_t vdz5_r3_account_mark_published(vdz5_handle *account);
ptrdiff_t vdz5_r3_account_sign(vdz5_handle *account,const uint8_t *bytes,size_t n,uint8_t *out,size_t cap);
vdz5_handle *vdz5_r3_olm_outbound(vdz5_handle *account,const uint8_t *peer_curve_b64,size_t n,const uint8_t *otk_curve_b64,size_t otk_n);
vdz5_handle *vdz5_r3_olm_inbound(vdz5_handle *account,const uint8_t *sender_curve_b64,size_t n,const uint8_t *prekey_b64,size_t m,uint8_t *plaintext,size_t cap);
ptrdiff_t vdz5_r3_olm_encrypt(vdz5_handle *session,const uint8_t *msg,size_t n,uint8_t *out_json,size_t cap); /* Matrix {type,body} JSON */
ptrdiff_t vdz5_r3_olm_decrypt(vdz5_handle *session,const uint8_t *msg_json,size_t n,uint8_t *plain,size_t cap);
vdz5_handle *vdz5_r3_megolm_outbound_new(void);
ptrdiff_t vdz5_r3_megolm_session_key(vdz5_handle *outbound,uint8_t *out,size_t cap); /* SECRET: do not log */
vdz5_handle *vdz5_r3_megolm_inbound_new(const uint8_t *key_b64,size_t n);
ptrdiff_t vdz5_r3_megolm_encrypt(vdz5_handle *outbound,const uint8_t *msg,size_t n,uint8_t *out_b64,size_t cap);
ptrdiff_t vdz5_r3_megolm_decrypt(vdz5_handle *inbound,const uint8_t *msg_b64,size_t n,uint8_t *plain,size_t cap);
ptrdiff_t vdz5_r3_session_id(vdz5_handle *session,uint8_t *out,size_t cap);
ptrdiff_t vdz5_r3_pickle_encrypted(vdz5_handle *handle,const uint8_t *key,size_t key_len,uint8_t *out,size_t cap);
vdz5_handle *vdz5_r3_unpickle_encrypted(uint32_t kind,const uint8_t *pickle,size_t n,const uint8_t *key,size_t key_len);
#ifdef __cplusplus
}
#endif
#endif

