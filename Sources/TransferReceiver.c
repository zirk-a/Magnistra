#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#ifdef __APPLE__
#include <CommonCrypto/CommonDigest.h>
#else
#include <openssl/sha.h>
#define CC_SHA256_CTX SHA256_CTX
#define CC_SHA256_Init SHA256_Init
#define CC_SHA256_Update SHA256_Update
#define CC_SHA256_Final SHA256_Final
#endif

extern int sodium_init(void);
extern void sodium_memzero(void *,size_t);
extern void randombytes_buf(void *,size_t);
extern int crypto_scalarmult_curve25519_base(unsigned char *,const unsigned char *);
extern int crypto_scalarmult_curve25519(unsigned char *,const unsigned char *,const unsigned char *);
extern int crypto_generichash(unsigned char *,size_t,const unsigned char *,unsigned long long,const unsigned char *,size_t);
extern int crypto_aead_xchacha20poly1305_ietf_decrypt(unsigned char *,unsigned long long *,unsigned char *,const unsigned char *,unsigned long long,const unsigned char *,unsigned long long,const unsigned char *,const unsigned char *);
extern int crypto_aead_xchacha20poly1305_ietf_encrypt(unsigned char *,unsigned long long *,const unsigned char *,unsigned long long,const unsigned char *,unsigned long long,const unsigned char *,const unsigned char *,const unsigned char *);
extern int mgtransfer_qr(const char *,uint8_t *,size_t);

#define MG_MAXFILE (16u*1024u*1024u)
#define MG_CHUNK 16384u
#define MG_FRMAX (MG_CHUNK+16u)
static pthread_mutex_t mtx=PTHREAD_MUTEX_INITIALIZER;
static pthread_t worker;
static int running=0, threaded=0, listener=-1, client=-1, state=0, decision=0;
static char docs[1024], qr[192], errtext[120], filetext[128];
static uint8_t secret[32], pubkey[32];
static uint32_t sas=0;
static time_t expires=0;

static int stopped(void){int x;pthread_mutex_lock(&mtx);x=!running;pthread_mutex_unlock(&mtx);return x;}
static void mgx_setstate(int s,const char *msg){pthread_mutex_lock(&mtx);state=s;if(msg)snprintf(errtext,sizeof(errtext),"%s",msg);pthread_mutex_unlock(&mtx);}
static uint32_t be32(const uint8_t *p){return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];}
static void tobe(uint8_t *p,uint32_t n){p[0]=(uint8_t)(n>>24);p[1]=(uint8_t)(n>>16);p[2]=(uint8_t)(n>>8);p[3]=(uint8_t)n;}
static int sendall(int fd,const void *v,size_t n){const uint8_t *p=v;while(n){if(stopped())return -1;ssize_t a=send(fd,p,n,0);if(a>0){p+=a;n-=a;}else if(a<0&&(errno==EINTR||errno==EAGAIN||errno==EWOULDBLOCK))continue;else return -1;}return 0;}
static int readall(int fd,void *v,size_t n,time_t deadline){uint8_t *p=v;while(n){if(stopped()||time(NULL)>deadline)return -1;ssize_t a=recv(fd,p,n,0);if(a>0){p+=a;n-=a;}else if(a<0&&(errno==EINTR||errno==EAGAIN||errno==EWOULDBLOCK))continue;else return -1;}return 0;}
static int wifiaddr(char ip[INET_ADDRSTRLEN]){
 struct ifaddrs *base=NULL;int ok=0;
 if(getifaddrs(&base))return 0;
 for(struct ifaddrs *it=base;it;it=it->ifa_next){
  if(it->ifa_addr&&it->ifa_addr->sa_family==AF_INET&&strcmp(it->ifa_name,"en0")==0
      &&(it->ifa_flags&IFF_UP)){
   struct sockaddr_in *sin=(struct sockaddr_in*)it->ifa_addr;
   uint32_t a=ntohl(sin->sin_addr.s_addr);
   /* A stale, loopback or link-local address must never be advertised to LegacyRelay. */
   if(!a||(a>>24)==127||(a>>16)==0xa9fe||(a>>24)>=224)continue;
   if(inet_ntop(AF_INET,&sin->sin_addr,ip,INET_ADDRSTRLEN)){ok=1;break;}
  }
 }
 freeifaddrs(base);return ok;
}

static int frame_recv(int fd,const uint8_t key[32],const char *kind,uint32_t seq,uint8_t *out,size_t max,size_t *got){
 uint8_t hdr[4],nonce[24],ad[32],cipher[MG_FRMAX];
 time_t end=time(NULL)+25;
 if(readall(fd,hdr,4,end)||readall(fd,nonce,24,end))return -1;
 uint32_t n=be32(hdr);if(n<17||n>MG_FRMAX||n>max+16)return -1;
 if(readall(fd,cipher,n,end))return -1;
 size_t k=strlen(kind);if(k>25)return -1;
 memcpy(ad,kind,k);tobe(ad+k,seq);
 unsigned long long m=0;
 int rc=crypto_aead_xchacha20poly1305_ietf_decrypt(out,&m,NULL,cipher,n,ad,k+4,nonce,key);
 sodium_memzero(cipher,sizeof(cipher));
 if(rc||m>max)return -1;
 *got=(size_t)m;return 0;
}
static int frame_send(int fd,const uint8_t key[32],const char *kind,uint32_t seq,const uint8_t *plain,size_t n){
 uint8_t nonce[24],out[MG_FRMAX],hdr[4],ad[32];unsigned long long outlen=0;
 if(n>MG_CHUNK)return -1;size_t k=strlen(kind);if(k>25)return -1;
 randombytes_buf(nonce,sizeof(nonce));memcpy(ad,kind,k);tobe(ad+k,seq);
 if(crypto_aead_xchacha20poly1305_ietf_encrypt(out,&outlen,plain,n,ad,k+4,NULL,nonce,key))return -1;
 tobe(hdr,(uint32_t)outlen);
 return sendall(fd,hdr,4)||sendall(fd,nonce,24)||sendall(fd,out,(size_t)outlen)?-1:0;
}
static int transfer(int fd){
 uint8_t hello[36],shared[32],krecv[32],ksend[32],hash[32],mix[80];
 if(readall(fd,hello,36,time(NULL)+15)||memcmp(hello,"MGX1",4))return -1;
 if(crypto_scalarmult_curve25519(shared,secret,hello+4))return -1;

 memcpy(mix,"MGX1SAS",7);memcpy(mix+7,pubkey,32);memcpy(mix+39,hello+4,32);
 if(crypto_generichash(hash,32,mix,71,shared,32))return -1;
 uint32_t v=be32(hash);pthread_mutex_lock(&mtx);sas=v%1000000;pthread_mutex_unlock(&mtx);
 memcpy(mix,"MGX1S2R",7);memcpy(mix+7,pubkey,32);memcpy(mix+39,hello+4,32);
 if(crypto_generichash(krecv,32,mix,71,shared,32))return -1;
 memcpy(mix,"MGX1R2S",7);memcpy(mix+7,pubkey,32);memcpy(mix+39,hello+4,32);
 if(crypto_generichash(ksend,32,mix,71,shared,32))return -1;
 sodium_memzero(shared,sizeof shared);
 mgx_setstate(2,NULL);
 time_t deadline=time(NULL)+30;
 int go=0;
 while(time(NULL)<=deadline&&!stopped()){
  pthread_mutex_lock(&mtx);go=decision;pthread_mutex_unlock(&mtx);
  if(go)break;usleep(100000);
 }
 if(go!=1){mgx_setstate(-1,"Transfer not approved");return -1;}
 uint8_t allowed='A';
 if(frame_send(fd,ksend,"MGX1-ALLOW",0,&allowed,1))return -1;
 mgx_setstate(3,NULL);
 uint8_t meta[256];size_t mn=0;
 if(frame_recv(fd,krecv,"MGX1-META",0,meta,sizeof(meta),&mn))return -1;
 if(mn<41||memcmp(meta,"FILE",4))return -1;
 uint32_t length=be32(meta+4);unsigned nameLen=meta[40];
 if(length<1||length>MG_MAXFILE||nameLen==0||nameLen>80||mn!=(size_t)41+nameLen)return -1;

 for(unsigned i=0;i<nameLen;i++){uint8_t c=meta[41+i];if(c<32||c>126||c=='/'||c=='\\')return -1;}
 char filename[82];memcpy(filename,meta+41,nameLen);filename[nameLen]=0;
 if(nameLen<10||strcmp(filename+nameLen-10,".mgsession")!=0)return -1;
 char partial[1200];if(snprintf(partial,sizeof partial,"%s/.magnistra-mgx-XXXXXX",docs)>=(int)sizeof partial)return -1;
 int out=mkstemp(partial);if(out<0)return -1;
 fchmod(out,S_IRUSR|S_IWUSR);
 CC_SHA256_CTX ctx;CC_SHA256_Init(&ctx);
 uint32_t left=length,seq=0;int success=1;uint8_t body[MG_CHUNK];
 while(left&&!stopped()){
  size_t n=0;
  if(frame_recv(fd,krecv,"MGX1-DATA",seq++,body,left<MG_CHUNK?left:MG_CHUNK,&n)||n==0||n>left){success=0;break;}
  CC_SHA256_Update(&ctx,body,(unsigned)n);
  size_t written=0;
  while(written<n){ssize_t w=write(out,body+written,n-written);if(w<1){success=0;break;}written+=(size_t)w;}
  if(!success)break;left-=(uint32_t)n;
 }
 uint8_t digest[32];CC_SHA256_Final(digest,&ctx);
 if(left||memcmp(digest,meta+8,32)||fsync(out))success=0;
 if(close(out))success=0;
 if(!success){unlink(partial);return -1;}

 char final[1200],saved[128];
 if(snprintf(final,sizeof final,"%s/MagnistraSession.mgsession",docs)>=(int)sizeof final){unlink(partial);return -1;}
 if(link(partial,final)==0){
  snprintf(saved,sizeof saved,"MagnistraSession.mgsession");
 }else{

  if(errno!=EEXIST){unlink(partial);return -1;}
  uint8_t random[8];randombytes_buf(random,sizeof random);
  char hex[17];for(int i=0;i<8;i++)sprintf(hex+i*2,"%02x",random[i]);hex[16]=0;
  snprintf(saved,sizeof saved,"LegacyRelay-%s.mgsession",hex);
  if(snprintf(final,sizeof final,"%s/%s",docs,saved)>=(int)sizeof final || link(partial,final)){
   unlink(partial);return -1;
  }
 }
 unlink(partial);
 pthread_mutex_lock(&mtx);snprintf(filetext,sizeof filetext,"%s",saved);pthread_mutex_unlock(&mtx);
 uint8_t ok='K';(void)frame_send(fd,ksend,"MGX1-RESULT",0,&ok,1);
 sodium_memzero(krecv,32);sodium_memzero(ksend,32);
 mgx_setstate(4,NULL);return 0;
}
static void *runner(void *unused){(void)unused;
 time_t deadline=expires;
 int socket_failed=0;
 while(!stopped()&&time(NULL)<=deadline){
  fd_set f;FD_ZERO(&f);FD_SET(listener,&f);struct timeval tv={1,0};
  int rv=select(listener+1,&f,NULL,NULL,&tv);
  if(rv<0){if(errno==EINTR||errno==EAGAIN)continue;socket_failed=1;break;}
  if(rv>0){struct sockaddr_in peer;socklen_t len=sizeof peer;
   int fd=accept(listener,(struct sockaddr*)&peer,&len);
   if(fd<0){if(errno==EINTR||errno==EAGAIN||errno==EWOULDBLOCK)continue;socket_failed=1;break;}
   pthread_mutex_lock(&mtx);client=fd;pthread_mutex_unlock(&mtx);
   struct timeval tv2={1,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv2,sizeof tv2);setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv2,sizeof tv2);
   if(transfer(fd)&&!stopped())mgx_setstate(-1,"Connection, authentication or file check failed");
   shutdown(fd,SHUT_RDWR);close(fd);
   pthread_mutex_lock(&mtx);client=-1;pthread_mutex_unlock(&mtx);
   break;
  }
 }
 if(!stopped()){
  pthread_mutex_lock(&mtx);int previous=state;pthread_mutex_unlock(&mtx);
  if(previous==1){
   if(socket_failed)mgx_setstate(-1,"Wi-Fi receiver socket stopped");
   else mgx_setstate(5,"Pairing expired");
  }
 }
 return NULL;
}
int mgx_start(const char *documentDir,char *qrOut,size_t qrCap){
 if(!documentDir||strlen(documentDir)>900||!qrOut||qrCap<192)return -1;
 pthread_mutex_lock(&mtx);int busy=running||threaded;pthread_mutex_unlock(&mtx);if(busy)return -2;
 if(sodium_init()<0)return -3;
 char ip[INET_ADDRSTRLEN]={0};if(!wifiaddr(ip)){
#ifdef MGX_TEST_ALLOW_LOOPBACK
 snprintf(ip,sizeof ip,"127.0.0.1");
#else
 return -4;
#endif
 }
 int sock=socket(AF_INET,SOCK_STREAM,0);if(sock<0)return -5;
 struct sockaddr_in addr;memset(&addr,0,sizeof addr);addr.sin_family=AF_INET;addr.sin_addr.s_addr=htonl(INADDR_ANY);addr.sin_port=htons(0);
 if(bind(sock,(struct sockaddr*)&addr,sizeof addr)||listen(sock,1)){close(sock);return -5;}
 socklen_t addrlen=sizeof addr;if(getsockname(sock,(struct sockaddr*)&addr,&addrlen)){close(sock);return -5;}
 randombytes_buf(secret,32);
 if(crypto_scalarmult_curve25519_base(pubkey,secret)){close(sock);return -3;}
 char hex[65];for(int i=0;i<32;i++)sprintf(hex+i*2,"%02x",pubkey[i]);hex[64]=0;
 int len=snprintf(qr,sizeof qr,"mgx1|%s|%u|%s",ip,(unsigned)ntohs(addr.sin_port),hex);
 if(len<=0||len>180){close(sock);return -6;}
 snprintf(qrOut,qrCap,"%s",qr);
 pthread_mutex_lock(&mtx);
 snprintf(docs,sizeof docs,"%s",documentDir);errtext[0]=0;filetext[0]=0;
 state=1;decision=0;sas=0;client=-1;listener=sock;running=1;expires=time(NULL)+60;threaded=1;
 pthread_mutex_unlock(&mtx);
 if(pthread_create(&worker,NULL,runner,NULL)){
  pthread_mutex_lock(&mtx);running=0;threaded=0;listener=-1;state=-1;pthread_mutex_unlock(&mtx);
  close(sock);sodium_memzero(secret,32);return -7;
 }
 return (int)ntohs(addr.sin_port);
}
void mgx_decide(int accept){pthread_mutex_lock(&mtx);if(state==2&&running)decision=accept?1:-1;pthread_mutex_unlock(&mtx);}
int mgx_state(void){pthread_mutex_lock(&mtx);int s=state;pthread_mutex_unlock(&mtx);return s;}
unsigned mgx_sas(void){pthread_mutex_lock(&mtx);unsigned s=sas;pthread_mutex_unlock(&mtx);return s;}
void mgx_message(char *out,size_t cap){if(!out||!cap)return;pthread_mutex_lock(&mtx);snprintf(out,cap,"%s",state==4?filetext:errtext);pthread_mutex_unlock(&mtx);}
void mgx_stop(void){
 pthread_mutex_lock(&mtx);int run=running;running=0;int s=listener,c=client,join=threaded;pthread_mutex_unlock(&mtx);
 if(!run&&!join)return;
 if(s>=0)shutdown(s,SHUT_RDWR);
 if(c>=0)shutdown(c,SHUT_RDWR);
 if(join)pthread_join(worker,NULL);
 if(s>=0)close(s);
 pthread_mutex_lock(&mtx);listener=-1;client=-1;threaded=0;state=0;decision=0;pthread_mutex_unlock(&mtx);
 sodium_memzero(secret,32);sodium_memzero(pubkey,32);
}
int mgx_qr(const char *payload,uint8_t *grid,size_t cap){return mgtransfer_qr(payload,grid,cap);}
