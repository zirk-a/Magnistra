#include <stdint.h>
#include <stddef.h>
#include <string.h>
#define S 49
#define TOTAL 242
#define DC 194
static int8_t g[S][S], reserved[S][S];
static void mark(int x,int y,int bit) {if(x>=0&&x<S&&y>=0&&y<S){g[y][x]=(int8_t)(bit!=0);reserved[y][x]=1;}}
static void finder(int cx,int cy){
 for(int y=-4;y<=4;y++)for(int x=-4;x<=4;x++){
  int d=x<0?-x:x, e=y<0?-y:y;
  mark(cx+x,cy+y,(d<=3&&e<=3&&(d==3||e==3||(d<=1&&e<=1))));
 }
}
static void align_(int cx,int cy){
 for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++){
  int a=x<0?-x:x,b=y<0?-y:y;
  mark(cx+x,cy+y,(a==2||b==2||(a==0&&b==0)));
 }
}
static uint8_t gf_mul(uint8_t a,uint8_t b){unsigned r=0; for(int i=7;i>=0;i--){r=(r<<1)^((r>>7)*0x11d);r^=((b>>i)&1)?a:0;}return (uint8_t)r;}
static void rs_divisor(uint8_t d[24]) {memset(d,0,24);d[23]=1;uint8_t root=1;
 for(int i=0;i<24;i++){for(int j=0;j<24;j++){d[j]=gf_mul(d[j],root);if(j+1<24)d[j]^=d[j+1];}root=gf_mul(root,2);}
}
static void rs_rem(const uint8_t* data,uint8_t ecc[24]){
 uint8_t div[24]; rs_divisor(div);memset(ecc,0,24);
 for(int i=0;i<97;i++) {uint8_t factor=data[i]^ecc[0];memmove(ecc,ecc+1,23);ecc[23]=0;
 for(int j=0;j<24;j++)ecc[j]^=gf_mul(div[j],factor);}
}
static void putbits(uint8_t* out,int* pos,unsigned val,int n){for(int i=n-1;i>=0;i--){int p=(*pos)++;if(p<DC*8)out[p>>3]|=((val>>i)&1)<<(7-(p&7));}}

int mgtransfer_qr(const char* str,uint8_t* out,size_t outlen){
 if(!str||!out||outlen<S*S)return 0;size_t n=strlen(str);if(n>192)return 0;
 uint8_t data[DC]={0};int bit=0;putbits(data,&bit,4,4);putbits(data,&bit,(unsigned)n,8);
 for(size_t i=0;i<n;i++)putbits(data,&bit,(uint8_t)str[i],8);
 putbits(data,&bit,0,(DC*8-bit)<4?(DC*8-bit):4);while(bit%8)putbits(data,&bit,0,1);
 for(int i=bit/8;i<DC;i++)data[i]=(uint8_t)((i-bit/8)%2?0x11:0xec);
 uint8_t e0[24],e1[24],all[TOTAL];rs_rem(data,e0);rs_rem(data+97,e1);
 int z=0;for(int i=0;i<97;i++){all[z++]=data[i];all[z++]=data[i+97];}
 for(int i=0;i<24;i++){all[z++]=e0[i];all[z++]=e1[i];}
 memset(g,-1,sizeof(g));memset(reserved,0,sizeof(reserved));
 finder(3,3); finder(S-4,3); finder(3,S-4);
 for(int i=8;i<S-8;i++){mark(i,6,i%2==0);mark(6,i,i%2==0);}
 align_(24,6);align_(6,24);align_(24,24);align_(42,24);align_(24,42);align_(42,42);

 for(int i=0;i<9;i++){if(i!=6)mark(8,i,0);if(i!=6)mark(i,8,0);}
 for(int i=0;i<8;i++){mark(S-1-i,8,0);mark(8,S-1-i,0);}
 mark(8,S-8,1);

 int vb=(8<<12);for(int i=17;i>=12;i--)if((vb>>i)&1)vb^=0x1f25<<(i-12);vb|=8<<12;
 for(int i=0;i<18;i++){int bitval=(vb>>i)&1;int a=S-11+i%3,b=i/3;
  mark(a,b,bitval);mark(b,a,bitval);
 }
 int k=0;for(int right=S-1;right>=1;right-=2){if(right==6)right=5;
  for(int vert=0;vert<S;vert++)for(int off=0;off<2;off++){
   int x=right-off,y=(((right+1)&2)==0)?(S-1-vert):vert;
   if(reserved[y][x])continue;
   int b=0;if(k<TOTAL*8)b=(all[k>>3]>>(7-(k&7)))&1;k++;
   g[y][x]=(int8_t)(b ^ (((x+y)&1)==0));
  }
 }

 int fb=(1<<13);for(int i=14;i>=10;i--)if((fb>>i)&1)fb^=0x537<<(i-10);fb=(((1<<3)|0)<<10)|(fb&0x3ff);fb^=0x5412;
 for(int i=0;i<=5;i++)mark(8,i,(fb>>i)&1);
 mark(8,7,(fb>>6)&1);mark(8,8,(fb>>7)&1);mark(7,8,(fb>>8)&1);
 for(int i=9;i<15;i++)mark(14-i,8,(fb>>i)&1);
 for(int i=0;i<8;i++)mark(S-1-i,8,(fb>>i)&1);
 for(int i=8;i<15;i++)mark(8,S-15+i,(fb>>i)&1);
 mark(8,S-8,1);
 for(int y=0;y<S;y++)for(int x=0;x<S;x++)out[y*S+x]=(uint8_t)(g[y][x]>0);
 return S;
}
