#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

extern int sodium_init(void);
extern void sodium_memzero(void *, size_t);
extern int crypto_pwhash_alg_argon2id13(void);
extern int crypto_pwhash(unsigned char *, unsigned long long, const char *,
                         unsigned long long, const unsigned char *,
                         unsigned long long, size_t, int);
extern int crypto_aead_xchacha20poly1305_ietf_decrypt(
    unsigned char *, unsigned long long *, unsigned char *, const unsigned char *,
    unsigned long long, const unsigned char *, unsigned long long,
    const unsigned char *, const unsigned char *);

#define MG_HEADER 68u
#define MG_TAG 16u
#define MG_MAX_FILE (8u * 1024u * 1024u)
#define MG_OPSLIMIT 3u
#define MG_MEMKIB 65536u
static const unsigned char mg_magic[12] = {'M','G','S','E','S','S','I','O','N','2',0,0};
static const char mg_domain[] = "LegacyRelay.mgsession.v2.credentials";
static size_t mg_bounded_len(const char *s,size_t limit) {
    size_t i=0;while(i<limit && s[i]) i++;return i;
}
static uint32_t mg_be32(const unsigned char *p) {
    return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
}
static void mg_put32(unsigned char *p,uint32_t v) {
    p[0]=(unsigned char)(v>>24);p[1]=(unsigned char)(v>>16);
    p[2]=(unsigned char)(v>>8);p[3]=(unsigned char)v;
}

int magnistra_v2_open(const unsigned char *src, size_t n,
                      const char *username, const char *password,
                      unsigned char **result, size_t *result_size) {
    unsigned char key[32] = {0};
    unsigned char credentials[sizeof(mg_domain)+4+256+4+1024] = {0};
    unsigned char *plain = NULL;
    size_t pos=0,u,p,ctlen;
    unsigned long long written=0;
    int status=-1;
    if (!result || !result_size) return -1;
    *result=NULL; *result_size=0;
    if (!src || !username || !password || n<MG_HEADER+MG_TAG+17u || n>MG_MAX_FILE+MG_HEADER) return -1;
    if (memcmp(src,mg_magic,sizeof(mg_magic))!=0 ||
        src[12]!=2 || src[13]!=1 || src[14]!=1 || src[15]!=1) return -1;
    if (mg_be32(src+16)!=MG_OPSLIMIT || mg_be32(src+20)!=MG_MEMKIB) return -1;
    ctlen=mg_be32(src+64);
    if (ctlen<MG_TAG+17u || ctlen>MG_MAX_FILE || MG_HEADER+ctlen!=n) return -1;
    u=mg_bounded_len(username,257u);p=mg_bounded_len(password,1025u);
    if (!u || !p || u>256 || p>1024) return -1;
    if (sodium_init()<0 || crypto_pwhash_alg_argon2id13()!=2) return -1;
    memcpy(credentials+pos,mg_domain,sizeof(mg_domain));pos+=sizeof(mg_domain);
    mg_put32(credentials+pos,(uint32_t)u);pos+=4;
    memcpy(credentials+pos,username,u);pos+=u;
    mg_put32(credentials+pos,(uint32_t)p);pos+=4;
    memcpy(credentials+pos,password,p);pos+=p;
    if (crypto_pwhash(key,32,(const char *)credentials,(unsigned long long)pos,
                      src+24,MG_OPSLIMIT,(size_t)MG_MEMKIB*1024u,
                      crypto_pwhash_alg_argon2id13())!=0) goto exit;
    plain=(unsigned char *)malloc(ctlen-MG_TAG);
    if (!plain) goto exit;
    if (crypto_aead_xchacha20poly1305_ietf_decrypt(
        plain,&written,NULL,src+MG_HEADER,(unsigned long long)ctlen,
        src,MG_HEADER,src+40,key)!=0) goto exit;
    if (written<17u || written>ctlen-MG_TAG ||
        memcmp(plain,"MGSPAY2\0",8)!=0 || plain[8]!=1 ||
        mg_be32(plain+9)>65536u ||
        (uint64_t)17u+mg_be32(plain+9)+mg_be32(plain+13)!=written) goto exit;
    *result=plain;
    *result_size=(size_t)written;
    plain=NULL;
    status=0;
exit:
    sodium_memzero(key,sizeof(key));
    sodium_memzero(credentials,sizeof(credentials));
    if (plain) { sodium_memzero(plain,ctlen-MG_TAG);free(plain); }
    return status;
}
void magnistra_v2_release(void *data,size_t n) {
    if (data) { sodium_memzero(data,n);free(data); }
}
