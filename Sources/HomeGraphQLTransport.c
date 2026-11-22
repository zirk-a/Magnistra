// Isolated Home GraphQL network experiment for iOS 5 ARMv7.
// Does not alter other Instagram transports or the session format.
// H2 capture, 2026-11-21: PolarisFeedRootPaginationCachedQuery_subscribe,
// doc_id 29614052288226084, POST /graphql/query.
#include "HomeGraphQLTransport.h"
#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

extern int magnistra_curl_process_init_once(void);
#define MAG_HOME_BODY_LIMIT (12u*1024u*1024u)
static unsigned char *g_body = NULL;
static size_t g_body_len = 0, g_body_cap = 0;
static long g_status = 0, g_tls = -1;
// Numeric stage diagnostics only. Never log request/body/token values.
static int g_stage = 0;
// Flags describe presence only, never token/cookie values.
static unsigned long g_ctx_flags=0;
static long g_bootstrap_status=0;
static long long g_bootstrap_bytes=0;
static long long g_graphql_post_bytes=0;
static int g_browser_post_headers=0;
static int g_seeded_count=0;
static int g_cookies_after_get=0;
static int g_csrf_changed=0;
static int g_seed_failure=0;

static int home_cookie_key(const char *header,const char *name) {
    const char *p=header;
    size_t n=strlen(name);
    if(!p || !n)return 0;
    while(*p) {
        while(*p==' ' || *p==';')p++;
        if(!strncmp(p,name,n) && p[n]=='=')return 1;
        p=strchr(p,';'); if(!p)break; p++;
    }
    return 0;
}


static void home_clear(void) {
    if (g_body) { free(g_body); g_body = NULL; }
    g_body_len = g_body_cap = 0;
    g_status = 0; g_tls = -1;
}
static size_t home_write(char *p,size_t unit,size_t n,void *ignored) {
    size_t amt, need, cap;
    unsigned char *np;
    (void)ignored;
    if (n && unit > SIZE_MAX / n) return 0;
    amt = unit * n;
    if (!amt) return 0;
    if (amt >= MAG_HOME_BODY_LIMIT || g_body_len > MAG_HOME_BODY_LIMIT - amt - 1) return 0;
    need = g_body_len + amt + 1;
    if (need > g_body_cap) {
        cap = g_body_cap ? g_body_cap : 16384;
        while (cap < need) {
            if (cap > MAG_HOME_BODY_LIMIT/2) {cap = MAG_HOME_BODY_LIMIT;break;}
            cap *= 2;
        }
        np = (unsigned char *)realloc(g_body,cap);
        if (!np) return 0;
        g_body=np;g_body_cap=cap;
    }
    memcpy(g_body+g_body_len,p,amt);
    g_body_len += amt;
    g_body[g_body_len]=0;
    return amt;
}
static int copy_between(const char *s,const char *a,const char *b,char *out,size_t max) {
    const char *start,*end;
    size_t n;
    if (!s || !a || !b || !out || max<2) return 0;
    start=strstr(s,a);
    if (!start) return 0;
    start+=strlen(a);
    end=strstr(start,b);
    if (!end) return 0;
    n=(size_t)(end-start);
    if (!n || n>=max) return 0;
    memcpy(out,start,n);out[n]=0;
    return 1;
}
static int dtsg_from_html(const char *html,char *out,size_t cap) {
    return copy_between(html,"[\"DTSGInitialData\",[],{\"token\":\"","\"",out,cap) ||
           copy_between(html,"name=\"fb_dtsg\" value=\"","\"",out,cap) ||
           copy_between(html,"name='fb_dtsg' value='","'",out,cap);
}
static int lsd_from_html(const char *html,char *out,size_t cap) {
    return copy_between(html,"[\"LSD\",[],{\"token\":\"","\"",out,cap) ||
           copy_between(html,"name=\"lsd\" value=\"","\"",out,cap) ||
           copy_between(html,"name='lsd' value='","'",out,cap);
}
static int jazoest_from_dtsg(const char *token,char *out,size_t cap) {
    const unsigned char *p=(const unsigned char*)token;
    unsigned long long sum=0;
    int n;
    if (!token || !token[0] || !out || cap<4) return 0;
    while (*p) sum += (unsigned long long)(*p++);
    n=snprintf(out,cap,"2%llu",sum);
    return n>0 && (size_t)n<cap;
}

static int home_rollout_hash(const char *html,char *out,size_t cap) {
    // Optional and page-specific. Missing hash => omit the header.
    int ok=copy_between(html,"\"rollout_hash\":\"","\"",out,cap) ||
           copy_between(html,"\"rollout_hash\": \"","\"",out,cap);
    if (ok) {
        const unsigned char *p=(const unsigned char*)out;
        while (*p) {
            if (!((*p>='A'&&*p<='Z')||(*p>='a'&&*p<='z')||
                  (*p>='0'&&*p<='9')||*p=='_'||*p=='-')) {
                out[0]=0;
                return 0;
            }
            p++;
        }
    }
    return ok;
}

static int home_extract_numeric(const char *html,const char *key,char *out,size_t cap) {
    const char *p,*q;size_t len;
    if (!html || !key || !out || cap<2) return 0;
    p=strstr(html,key);if (!p)return 0;p+=strlen(key);
    if (*p=='"')p++;
    q=p;while (*q>='0' && *q<='9')q++;
    len=(size_t)(q-p);
    if (!len || len>=cap)return 0;
    memcpy(out,p,len);out[len]=0;return 1;
}
static int home_cookie_id(const char *cookies,char *out,size_t cap) {
    const char *p=cookies;size_t n;
    if (!p || !out || cap<2)return 0;
    while (*p) {
        while (*p==' ' || *p==';')p++;
        if (!strncmp(p,"ds_user_id=",11)) {
            p+=11;n=strcspn(p,"; ");
            if (!n || n>=cap)return 0;
            memcpy(out,p,n);out[n]=0;return 1;
        }
        p=strchr(p,';');if (!p)break;p++;
    }
    return 0;
}
static int home_form_field(CURL *encoder,char *post,size_t cap,const char *key,const char *value) {
    char *escaped;size_t used;int n;
    if (!encoder || !post || !key || !value || !value[0])return 1;
    escaped=curl_easy_escape(encoder,value,0);
    if (!escaped)return 0;
    used=strlen(post);if (used>=cap)return 0;
    n=snprintf(post+used,cap-used,"&%s=%s",key,escaped);
    curl_free(escaped);
    return n>0 && (size_t)n<cap-used;
}

static void home_wipe(void *ptr,size_t n) {
    volatile unsigned char *p=(volatile unsigned char *)ptr;
    while (n--) *p++=0;
}

// The input session header is already validated by the original Swift loader.
// Add it to a libcurl cookie engine with a scope matching this Home endpoint.
// No cookie values are written to files or logged.
static int home_seed_shared_cookies(CURLSH *share,const char *cookies) {
    CURL *h=NULL;
    const char *p,*end,*trim;
    size_t n;
    int count=0,ok=1;
    char *line=NULL;
    if(!share || !cookies || !cookies[0])return 0;
    h=curl_easy_init();if(!h)return 0;
    if(curl_easy_setopt(h,CURLOPT_SHARE,share)!=CURLE_OK ||
       curl_easy_setopt(h,CURLOPT_COOKIEFILE,"")!=CURLE_OK) {ok=0;goto done;}
    p=cookies;
    while(*p) {
        while(*p==' ' || *p==';')p++;
        if(!*p)break;
        end=strchr(p,';');if(!end)end=p+strlen(p);
        trim=end;
        while(trim>p && trim[-1]==' ')trim--;
        n=(size_t)(trim-p);
        // Don't silently truncate or accept malformed fields.
        if(!n || n>65535 || !memchr(p,'=',n)) {ok=0;break;}
        line=(char*)malloc(n+100);
        if(!line){ok=0;break;}
        snprintf(line,n+100,"Set-Cookie: %.*s; Domain=www.instagram.com; Path=/; Secure",(int)n,p);
        if(curl_easy_setopt(h,CURLOPT_COOKIELIST,line)!=CURLE_OK){ok=0;break;}
        home_wipe(line,n+100);free(line);line=NULL;
        count++;
        p=(*end)?end+1:end;
    }
done:
    if(line){home_wipe(line,strlen(line));free(line);}
    curl_easy_cleanup(h);
    g_seeded_count=count;
    return ok && count>0;
}
// Count cookies and retrieve only the current CSRF cookie internally.
// The cookie list is never logged or stored, and values are wiped.
static int home_cookie_state(CURLSH *share,char *csrf,size_t csrf_cap,int *count) {
    CURL *h=NULL;struct curl_slist *list=NULL,*item;
    int success=0;
    if(count)*count=0;
    if(csrf && csrf_cap)csrf[0]=0;
    h=curl_easy_init();if(!h)return 0;
    if(curl_easy_setopt(h,CURLOPT_SHARE,share)!=CURLE_OK ||
       curl_easy_setopt(h,CURLOPT_COOKIEFILE,"")!=CURLE_OK)goto done;
    if(curl_easy_getinfo(h,CURLINFO_COOKIELIST,&list)!=CURLE_OK)goto done;
    success=1;
    for(item=list;item;item=item->next){
        const char *p=item->data,*name=NULL,*value=NULL;
        int col=0;
        // Netscape cookie list: domain, tailmatch, path, secure, expires, name, value.
        if(count)(*count)++;
        while(p && *p){
            if(col==5)name=p;
            if(col==6){value=p;break;}
            p=strchr(p,'\t');if(!p)break;
            p++;col++;
        }
        if(name && value && (size_t)(value-name)>=10 &&
           !strncmp(name,"csrftoken\t",10) && csrf && csrf_cap){
            size_t n=strlen(value);
            if(n && n<csrf_cap){memcpy(csrf,value,n+1);}
        }
    }
done:
    if(list)curl_slist_free_all(list);
    curl_easy_cleanup(h);
    return success;
}

static CURLcode home_request(const char *url,const char *ca,const char *ua,
      const char *language,const char *cookies,const char *csrf,const char *post,const char *lsd,
      CURLSH *cookie_share,const char *ajax_hash) {
    CURL *curl;CURLcode rc;
    struct curl_slist *head=NULL;
    char lang[256],csrf_head[1024],lsd_head[1024];
    if (!url || !ca || !ua || !cookies || !csrf || !cookie_share) return CURLE_BAD_FUNCTION_ARGUMENT;
    home_clear();
    curl=curl_easy_init();
    if (!curl) return CURLE_FAILED_INIT;
    snprintf(lang,sizeof(lang),"Accept-Language: %s", language && language[0]?language:"en-US");
    snprintf(csrf_head,sizeof(csrf_head),"X-CSRFToken: %s",csrf);
    if (post) {
        head=curl_slist_append(head,"Accept: */*");
        head=curl_slist_append(head,"X-Requested-With: XMLHttpRequest");
        head=curl_slist_append(head,"Sec-Fetch-Site: same-origin");
        head=curl_slist_append(head,"Sec-Fetch-Mode: cors");
        head=curl_slist_append(head,"Sec-Fetch-Dest: empty");
    } else {
        // The initial GET is a document navigation, not an XHR. Without
        // document headers, Instagram may serve the anonymous HTML shell.
        head=curl_slist_append(head,"Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
        head=curl_slist_append(head,"Upgrade-Insecure-Requests: 1");
        head=curl_slist_append(head,"Sec-Fetch-Site: none");
        head=curl_slist_append(head,"Sec-Fetch-Mode: navigate");
        head=curl_slist_append(head,"Sec-Fetch-Dest: document");
    }
    head=curl_slist_append(head,lang);
    head=curl_slist_append(head,"Referer: https://www.instagram.com/");
    if (post) {
        head=curl_slist_append(head,csrf_head);
        head=curl_slist_append(head,"X-IG-App-ID: 1217981644879628");
        head=curl_slist_append(head,"X-ASBD-ID: 359341");
        head=curl_slist_append(head,"X-IG-WWW-Claim: 0");
        g_browser_post_headers |= 1;
        if (ajax_hash && ajax_hash[0]) {
            char ajax_head[256];
            snprintf(ajax_head,sizeof(ajax_head),"X-Instagram-AJAX: %s",ajax_hash);
            head=curl_slist_append(head,ajax_head);
            g_browser_post_headers |= 2;
        }

        head=curl_slist_append(head,"Content-Type: application/x-www-form-urlencoded");
        head=curl_slist_append(head,"Origin: https://www.instagram.com");
        head=curl_slist_append(head,"X-FB-Friendly-Name: PolarisFeedRootPaginationCachedQuery_subscribe");
        // FULL trace: x-root-field-name value length 39, matching this field.
        head=curl_slist_append(head,"X-Root-Field-Name: xdt_api__v1__feed__timeline__connection");
        if (lsd && lsd[0]) {
            snprintf(lsd_head,sizeof(lsd_head),"X-FB-LSD: %s",lsd);
            head=curl_slist_append(head,lsd_head);
        }
    }
    curl_easy_setopt(curl,CURLOPT_URL,url);
    curl_easy_setopt(curl,CURLOPT_HTTPHEADER,head);
    curl_easy_setopt(curl,CURLOPT_USERAGENT,ua);
    // Use the cookie jar, not a fixed Cookie header: GET Set-Cookie updates
    // must reach the next GraphQL POST in the same Home operation.
    curl_easy_setopt(curl,CURLOPT_SHARE,cookie_share);
    curl_easy_setopt(curl,CURLOPT_COOKIEFILE,"");
    curl_easy_setopt(curl,CURLOPT_CAINFO,ca);
    curl_easy_setopt(curl,CURLOPT_SSL_VERIFYPEER,1L);
    curl_easy_setopt(curl,CURLOPT_SSL_VERIFYHOST,2L);
    curl_easy_setopt(curl,CURLOPT_ACCEPT_ENCODING,"gzip, deflate");
    curl_easy_setopt(curl,CURLOPT_WRITEFUNCTION,home_write);
    curl_easy_setopt(curl,CURLOPT_FOLLOWLOCATION,0L);
    curl_easy_setopt(curl,CURLOPT_CONNECTTIMEOUT,15L);
    curl_easy_setopt(curl,CURLOPT_TIMEOUT,45L);
    if (post) {
        curl_easy_setopt(curl,CURLOPT_POST,1L);
        curl_easy_setopt(curl,CURLOPT_POSTFIELDS,post);
        curl_easy_setopt(curl,CURLOPT_POSTFIELDSIZE,(long)strlen(post));
    } else curl_easy_setopt(curl,CURLOPT_HTTPGET,1L);
    rc=curl_easy_perform(curl);
    curl_easy_getinfo(curl,CURLINFO_RESPONSE_CODE,&g_status);
    curl_easy_getinfo(curl,CURLINFO_SSL_VERIFYRESULT,&g_tls);
    curl_slist_free_all(head);
    curl_easy_cleanup(curl);
    return rc;
}
int magnistra_home_graphql_fetch(const char *ca_path,const char *user_agent,
    const char *language,const char *cookies,const char *csrf,const char *variables_json) {
    CURLcode rc;
    CURL *encoder=NULL;
    char dtsg[1024]={0},jazoest[4096]={0},lsd[1024]={0};
    char revision[64]={0},haste[160]={0},hsi[96]={0},spin_b[96]={0},spin_t[64]={0},av[96]={0};
    char rollout_hash[160]={0};
    char *a=NULL,*b=NULL,*v=NULL,*l=NULL,*post=NULL;
    CURLSH *cookie_share=NULL;
    char effective_csrf[1024]={0},updated_csrf[1024]={0};
    size_t required;
    int result=0;
    home_clear();
    g_ctx_flags=0;g_bootstrap_status=0;g_bootstrap_bytes=0;g_graphql_post_bytes=0;
    g_seeded_count=0;g_cookies_after_get=0;g_csrf_changed=0;g_seed_failure=0;
    g_browser_post_headers=0;
    if (home_cookie_key(cookies,"sessionid"))g_ctx_flags|=1UL;
    if (home_cookie_key(cookies,"ds_user_id"))g_ctx_flags|=2UL;
    if (home_cookie_key(cookies,"csrftoken"))g_ctx_flags|=4UL;
    g_stage=1; // input validation
    if (!ca_path || !ca_path[0] || !user_agent || !user_agent[0] ||
        !cookies || !cookies[0] || !csrf || !csrf[0] || !variables_json ||
        variables_json[0]!='{' || strlen(variables_json)>64000) return -1000;
    if (magnistra_curl_process_init_once()!=0) return -1001;
    cookie_share=curl_share_init();
    if(!cookie_share ||
       curl_share_setopt(cookie_share,CURLSHOPT_SHARE,CURL_LOCK_DATA_COOKIE)!=CURLSHE_OK ||
       !home_seed_shared_cookies(cookie_share,cookies)) {
        g_seed_failure=1;result=-1010;goto done;
    }
    snprintf(effective_csrf,sizeof(effective_csrf),"%s",csrf);
    g_stage=2; // initial authenticated web request
    rc=home_request("https://www.instagram.com/",ca_path,user_agent,language,cookies,effective_csrf,NULL,NULL,cookie_share,NULL);
    g_bootstrap_status=g_status;
    g_bootstrap_bytes=(long long)g_body_len;
    if (rc != CURLE_OK) {result=(int)rc; goto done;}
    if (g_status!=200 || g_tls!=0 || !g_body || !g_body_len) {
        result= -1002;goto done;
    }
    // Mirror the browser: incorporate any cookie updates from the HTML GET.
    if(home_cookie_state(cookie_share,updated_csrf,sizeof(updated_csrf),&g_cookies_after_get)) {
        if(updated_csrf[0] && strcmp(updated_csrf,effective_csrf)!=0) {
            snprintf(effective_csrf,sizeof(effective_csrf),"%s",updated_csrf);
            g_csrf_changed=1;
        }
    }
    g_stage=3; // token extraction
    if (strstr((const char *)g_body,"DTSGInitialData"))g_ctx_flags|=128UL;
    if (strstr((const char *)g_body,"Polaris"))g_ctx_flags|=256UL;
    (void)lsd_from_html((const char *)g_body,lsd,sizeof(lsd));
    if (lsd[0])g_ctx_flags|=16UL;
    // Optional per-page Relay controls (values never logged or saved).
    (void)home_extract_numeric((const char*)g_body,"\"server_revision\":",revision,sizeof(revision));
    if (!revision[0]) (void)home_extract_numeric((const char*)g_body,"\"client_revision\":",revision,sizeof(revision));
    (void)copy_between((const char*)g_body,"\"haste_session\":\"","\"",haste,sizeof(haste));
    (void)copy_between((const char*)g_body,"\"hsi\":\"","\"",hsi,sizeof(hsi));
    (void)copy_between((const char*)g_body,"\"spin_b\":\"","\"",spin_b,sizeof(spin_b));
    (void)home_extract_numeric((const char*)g_body,"\"spin_t\":",spin_t,sizeof(spin_t));
    (void)home_rollout_hash((const char*)g_body,rollout_hash,sizeof(rollout_hash));
    (void)home_cookie_id(cookies,av,sizeof(av));
    if (!dtsg_from_html((const char *)g_body,dtsg,sizeof(dtsg))) {
        g_status=462;
        result=-1003; goto done;
    }
    g_ctx_flags|=8UL; // fb_dtsg was parsed successfully.
    if (!copy_between((const char *)g_body,"name=\"jazoest\" value=\"","\"",jazoest,sizeof(jazoest)) &&
        !copy_between((const char *)g_body,"name='jazoest' value='","'",jazoest,sizeof(jazoest)) &&
        !jazoest_from_dtsg(dtsg,jazoest,sizeof(jazoest))) {
        result=-1004;goto done;
    }
    if(jazoest[0])g_ctx_flags|=32UL;
    if(revision[0])g_ctx_flags|=64UL;
    if(av[0])g_ctx_flags|=512UL;
    encoder=curl_easy_init();
    if (!encoder) {result=-1005;goto done;}
    a=curl_easy_escape(encoder,dtsg,0);
    b=curl_easy_escape(encoder,jazoest,0);
    v=curl_easy_escape(encoder,variables_json,0);
    if (lsd[0]) l=curl_easy_escape(encoder,lsd,0);
    if (!a || !b || !v || (lsd[0] && !l)) {result=-1006;goto done;}
    required=strlen(a)+strlen(b)+strlen(v)+(l?strlen(l):0)+4096;
    post=(char*)malloc(required);
    if (!post) {result=-1007;goto done;}
    snprintf(post,required,"fb_dtsg=%s&jazoest=%s&variables=%s"
      "&doc_id=29614052288226084"
      "&fb_api_caller_class=RelayModern"
      "&fb_api_req_friendly_name=PolarisFeedRootPaginationCachedQuery_subscribe"
      "&server_timestamps=true",a,b,v);
    if (l) { strncat(post,"&lsd=",required-strlen(post)-1); strncat(post,l,required-strlen(post)-1); }
    // H3 contained these additional Relay keys. Static defaults are only
    // used for non-secret web transport controls; runtime values come from HTML.
    if (strlen(post)+99>=required) { result=-1008;goto done; }
    strcat(post,"&__a=1&__d=www&__user=0&__req=1&__comet_req=7&dpr=1&__ccg=UNKNOWN");
    if (!home_form_field(encoder,post,required,"av",av) ||
        !home_form_field(encoder,post,required,"__rev",revision) ||
        !home_form_field(encoder,post,required,"__spin_r",revision) ||
        !home_form_field(encoder,post,required,"__hs",haste) ||
        !home_form_field(encoder,post,required,"__hsi",hsi) ||
        !home_form_field(encoder,post,required,"__spin_b",spin_b) ||
        !home_form_field(encoder,post,required,"__spin_t",spin_t)) {
        result=-1009;goto done;
    }
    g_graphql_post_bytes=(long long)strlen(post);
    g_stage=4; // GraphQL request
    rc=home_request("https://www.instagram.com/graphql/query",ca_path,user_agent,language,cookies,effective_csrf,post,lsd,cookie_share,rollout_hash);
    g_stage=5; // response available, even if HTTP failed
    result=(int)rc;
done:
    if (post) {home_wipe(post,strlen(post));free(post);}
    if (a)curl_free(a);
    if (b)curl_free(b);
    if (v)curl_free(v);
    if (l)curl_free(l);
    if (encoder)curl_easy_cleanup(encoder);
    home_wipe(dtsg,sizeof(dtsg));
    home_wipe(jazoest,sizeof(jazoest));
    home_wipe(lsd,sizeof(lsd));
    home_wipe(effective_csrf,sizeof(effective_csrf));
    home_wipe(updated_csrf,sizeof(updated_csrf));
    if(cookie_share)curl_share_cleanup(cookie_share);
    home_wipe(revision,sizeof(revision));
    home_wipe(haste,sizeof(haste));
    home_wipe(hsi,sizeof(hsi));
    home_wipe(spin_b,sizeof(spin_b));
    home_wipe(spin_t,sizeof(spin_t));
    home_wipe(av,sizeof(av));
    home_wipe(rollout_hash,sizeof(rollout_hash));
    return result;
}
long magnistra_home_graphql_http_status(void) {return g_status;}
long magnistra_home_graphql_tls_verify_result(void) {return g_tls;}
const unsigned char *magnistra_home_graphql_body(void) {return g_body;}
long long magnistra_home_graphql_body_length(void) {return (long long)g_body_len;}

int magnistra_home_graphql_stage(void) {return g_stage;}

unsigned long magnistra_home_graphql_ctx_flags(void){return g_ctx_flags;}
long magnistra_home_graphql_bootstrap_status(void){return g_bootstrap_status;}
long long magnistra_home_graphql_bootstrap_bytes(void){return g_bootstrap_bytes;}
long long magnistra_home_graphql_post_bytes(void){return g_graphql_post_bytes;}

int magnistra_home_graphql_cookie_seeded(void){return g_seeded_count;}
int magnistra_home_graphql_cookie_after_get(void){return g_cookies_after_get;}
int magnistra_home_graphql_cookie_csrf_changed(void){return g_csrf_changed;}
int magnistra_home_graphql_cookie_seed_failed(void){return g_seed_failure;}

int magnistra_home_graphql_browser_header_flags(void){return g_browser_post_headers;}
