/* Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md. */
#include "opus_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <ogg/ogg.h>
#include <opus/opus.h>

#define OPUS_OUT_RATE 48000
#define MAX_FRAME     5760

static void write_le32(unsigned char *p, unsigned int v) {
    p[0] = (unsigned char)(v);       p[1] = (unsigned char)(v >> 8);
    p[2] = (unsigned char)(v >> 16); p[3] = (unsigned char)(v >> 24);
}
static void write_le16(unsigned char *p, unsigned short v) {
    p[0] = (unsigned char)(v); p[1] = (unsigned char)(v >> 8);
}

static int write_wav_header(FILE *f, int channels, int sampleRate, unsigned int dataBytes) {
    unsigned char h[44];
    unsigned int byteRate = (unsigned int)(sampleRate * channels * 2);
    memcpy(h, "RIFF", 4);
    write_le32(h + 4, 36 + dataBytes);
    memcpy(h + 8, "WAVE", 4);
    memcpy(h + 12, "fmt ", 4);
    write_le32(h + 16, 16);
    write_le16(h + 20, 1);
    write_le16(h + 22, (unsigned short)channels);
    write_le32(h + 24, (unsigned int)sampleRate);
    write_le32(h + 28, byteRate);
    write_le16(h + 32, (unsigned short)(channels * 2));
    write_le16(h + 34, 16);
    memcpy(h + 36, "data", 4);
    write_le32(h + 40, dataBytes);
    if (fseek(f, 0, SEEK_SET) != 0) return -1;
    if (fwrite(h, 1, 44, f) != 44) return -1;
    return 0;
}

int opus_ogg_to_wav(const char *inPath, const char *outPath) {
    FILE *in = fopen(inPath, "rb");
    if (!in) return -1;
    FILE *out = fopen(outPath, "wb");
    if (!out) { fclose(in); return -2; }

    unsigned char zero[44];
    memset(zero, 0, sizeof(zero));
    fwrite(zero, 1, 44, out);

    ogg_sync_state oy;
    ogg_stream_state os;
    ogg_page og;
    ogg_packet op;
    ogg_sync_init(&oy);

    int stream_init = 0;
    int have_head = 0;
    long packet_count = 0;
    int channels = 0;
    int err = 0;
    long skip_remaining = 0;
    OpusDecoder *dec = NULL;
    opus_int16 *pcm = NULL;
    unsigned int dataBytes = 0;
    int rc = 0;
    int eof = 0;

    while (!eof) {
        char *buf = ogg_sync_buffer(&oy, 4096);
        size_t n = fread(buf, 1, 4096, in);
        ogg_sync_wrote(&oy, (long)n);
        if (n == 0) eof = 1;

        while (ogg_sync_pageout(&oy, &og) == 1) {
            if (!stream_init) {
                ogg_stream_init(&os, ogg_page_serialno(&og));
                stream_init = 1;
            }
            if (ogg_stream_pagein(&os, &og) != 0) continue;

            while (ogg_stream_packetout(&os, &op) == 1) {
                if (packet_count == 0) {

                    if (op.bytes < 19 || memcmp(op.packet, "OpusHead", 8) != 0) { rc = -3; goto done; }
                    channels = op.packet[9];
                    if (channels < 1 || channels > 2) { rc = -4; goto done; }
                    skip_remaining = (long)(op.packet[10] | (op.packet[11] << 8));
                    dec = opus_decoder_create(OPUS_OUT_RATE, channels, &err);
                    if (!dec || err != OPUS_OK) { rc = -5; goto done; }
                    pcm = (opus_int16 *)malloc(sizeof(opus_int16) * MAX_FRAME * channels);
                    if (!pcm) { rc = -6; goto done; }
                    have_head = 1;
                } else if (packet_count == 1) {

                } else {
                    int samples = opus_decode(dec, op.packet, (opus_int32)op.bytes,
                                              pcm, MAX_FRAME, 0);
                    if (samples > 0) {
                        int start = 0;
                        if (skip_remaining > 0) {
                            int s = samples < skip_remaining ? samples : (int)skip_remaining;
                            start = s;
                            skip_remaining -= s;
                        }
                        int frames = samples - start;
                        if (frames > 0) {
                            size_t count = (size_t)frames * (size_t)channels;
                            if (fwrite(pcm + (size_t)start * (size_t)channels,
                                       sizeof(opus_int16), count, out) != count) { rc = -7; goto done; }
                            dataBytes += (unsigned int)(count * 2);
                        }
                    }

                }
                packet_count++;
            }
        }
    }
    if (!have_head) rc = -8;

done:
    if (dec) opus_decoder_destroy(dec);
    if (pcm) free(pcm);
    if (stream_init) ogg_stream_clear(&os);
    ogg_sync_clear(&oy);

    if (rc == 0) {
        if (write_wav_header(out, channels, OPUS_OUT_RATE, dataBytes) != 0) rc = -9;
    }
    fclose(out);
    fclose(in);
    if (rc != 0) remove(outPath);
    return rc;
}

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <opus/opus.h>

static uint16_t mg_vo_u16(const unsigned char *p) {
    return (uint16_t)(p[0] | ((uint16_t)p[1] << 8));
}
static uint32_t mg_vo_u32(const unsigned char *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}
static void mg_vo_put(unsigned char *p,uint64_t value,int bytes){
    int i;for(i=0;i<bytes;i++)p[i]=(unsigned char)((value>>(i*8))&255u);
}
static int mg_vo_page(FILE *f,const unsigned char *packet,size_t bytes,
                      unsigned char flags,uint64_t granule,uint32_t serial,uint32_t seq){
    unsigned char page[2048];uint32_t crc=0;size_t segments=bytes/255+1;
    size_t header=27+segments;size_t length=header+bytes;size_t i,j,rest=bytes;
    if(bytes>1275||segments>255||length>sizeof(page))return -1;
    memset(page,0,length);memcpy(page,"OggS",4);page[4]=0;page[5]=flags;
    mg_vo_put(page+6,granule,8);mg_vo_put(page+14,serial,4);
    mg_vo_put(page+18,seq,4);page[26]=(unsigned char)segments;
    for(i=0;i<segments;i++){
        size_t n=rest>=255?255:rest;page[27+i]=(unsigned char)n;rest-=n;
    }
    memcpy(page+header,packet,bytes);

    for(i=0;i<length;i++){
        crc^=(uint32_t)page[i]<<24;
        for(j=0;j<8;j++)crc=(crc&0x80000000u)?(crc<<1)^0x04c11db7u:crc<<1;
    }
    mg_vo_put(page+22,crc,4);
    return fwrite(page,1,length,f)==length?0:-1;
}

int magnistra_direct_voice_wav_to_ogg_opus(const char *source,const char *target){
    FILE *in=NULL,*out=NULL;unsigned char chunk[8],header[12],fmt[40];
    int16_t *samples=NULL;OpusEncoder *encoder=NULL;
    int ret=-1,opus_error=0,lookahead=0;size_t count=0;
    long data_at=-1;uint32_t bytes=0;uint32_t fmt_size=0;
    uint16_t format=0,channels=0,bitdepth=0;uint32_t rate=0;
    uint32_t serial,seq=0;size_t frames,frame_index,j;
    unsigned char head[19],tags[64],packet[1275];int16_t frame[320];
    if(!source||!target||!source[0]||!target[0]||strcmp(source,target)==0)return -7601;
    in=fopen(source,"rb");if(!in)return -7602;
    if(fread(header,1,12,in)!=12||memcmp(header,"RIFF",4)||memcmp(header+8,"WAVE",4)){
        ret=-7603;goto done;
    }
    while(fread(chunk,1,8,in)==8){
        uint32_t len=mg_vo_u32(chunk+4);long payload=ftell(in);
        if(payload<0 || len>15000000u){ret=-7604;goto done;}
        if(!memcmp(chunk,"fmt ",4)){
            if(len<16||len>sizeof(fmt)||fread(fmt,1,len,in)!=len){ret=-7605;goto done;}
            fmt_size=len;format=mg_vo_u16(fmt);channels=mg_vo_u16(fmt+2);
            rate=mg_vo_u32(fmt+4);bitdepth=mg_vo_u16(fmt+14);
        }else if(!memcmp(chunk,"data",4)){
            data_at=payload;bytes=len;
        }
        if(fseek(in,payload+(long)len+(len&1u),SEEK_SET)!=0){ret=-7606;goto done;}
        if(data_at>=0 && fmt_size)break;
    }
    if(!fmt_size || data_at<0 || format!=1 || channels!=1 || rate!=16000 ||
       bitdepth!=16 || !bytes || (bytes&1u) || bytes>120u*16000u*2u){
        ret=-7607;goto done;
    }
    count=bytes/2;samples=(int16_t *)malloc(bytes);
    if(!samples){ret=-7608;goto done;}
    if(fseek(in,data_at,SEEK_SET)!=0||fread(samples,1,bytes,in)!=bytes){ret=-7609;goto done;}
    { size_t i;for(i=0;i<count;i++){
        unsigned char *p=(unsigned char*)samples+i*2;
        samples[i]=(int16_t)mg_vo_u16(p);
    }}
    encoder=opus_encoder_create(16000,1,OPUS_APPLICATION_VOIP,&opus_error);
    if(!encoder||opus_error!=OPUS_OK){ret=-7610;goto done;}
    if(opus_encoder_ctl(encoder,OPUS_SET_BITRATE(24000))!=OPUS_OK){ret=-7611;goto done;}
    if(opus_encoder_ctl(encoder,OPUS_GET_LOOKAHEAD(&lookahead))!=OPUS_OK||
       lookahead<0||lookahead>2000){ret=-7612;goto done;}
    frames=(count+(size_t)lookahead+319u)/320u;
    if(!frames){ret=-7613;goto done;}
    out=fopen(target,"wb");if(!out){ret=-7614;goto done;}
    serial=(uint32_t)time(NULL) ^ ((uint32_t)count<<9) ^ (uint32_t)(uintptr_t)encoder;
    memset(head,0,sizeof(head));memcpy(head,"OpusHead",8);head[8]=1;head[9]=1;
    mg_vo_put(head+10,(uint16_t)(lookahead*3),2);
    mg_vo_put(head+12,16000,4);
    if(mg_vo_page(out,head,sizeof(head),2,0,serial,seq++)!=0){ret=-7615;goto done;}
    memset(tags,0,sizeof(tags));memcpy(tags,"OpusTags",8);
    mg_vo_put(tags+8,8,4);memcpy(tags+12,"Magnistra",8);
    mg_vo_put(tags+20,0,4);
    if(mg_vo_page(out,tags,24,0,0,serial,seq++)!=0){ret=-7616;goto done;}
    for(frame_index=0;frame_index<frames;frame_index++){
        int written;uint64_t granule;unsigned char flags=0;
        for(j=0;j<320;j++){
            int64_t index=(int64_t)(frame_index*320+j)-(int64_t)lookahead;
            frame[j]=(index>=0 && (size_t)index<count)?samples[index]:0;
        }
        written=opus_encode(encoder,frame,320,packet,sizeof(packet));
        if(written<=0 || written>(int)sizeof(packet)){ret=-7617;goto done;}
        granule=(uint64_t)(frame_index+1u)*960u;
        if(frame_index+1u==frames){
            granule=(uint64_t)(count+(size_t)lookahead)*3u;flags=4;
        }
        if(mg_vo_page(out,packet,(size_t)written,flags,granule,serial,seq++)!=0){
            ret=-7618;goto done;
        }
    }
    if(fflush(out)!=0){ret=-7619;goto done;}
    ret=0;
done:
    if(out){if(fclose(out)!=0)ret=-7620;out=NULL;}
    if(ret!=0 && target && target[0])remove(target);
    if(encoder)opus_encoder_destroy(encoder);
    if(samples)free(samples);
    if(in)fclose(in);
    return ret;
}

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <opus/opus.h>
static void mg_wr16(unsigned char *p,unsigned v){p[0]=(unsigned char)v;p[1]=(unsigned char)(v>>8);}
static void mg_wr32(unsigned char *p,unsigned v){mg_wr16(p,v);mg_wr16(p+2,v>>16);}
int magnistra_direct_decode_ogg_opus_to_wav(const char *input, const char *output){
 if(!input||!output||!input[0]||!output[0])return -1;
 FILE *f=fopen(input,"rb");if(!f)return -2;
 if(fseek(f,0,SEEK_END)!=0){fclose(f);return -3;}
 long length=ftell(f);if(length<64||length>16000000){fclose(f);return -4;}
 rewind(f);unsigned char *src=(unsigned char*)malloc((size_t)length);
 if(!src){fclose(f);return -5;}
 if(fread(src,1,(size_t)length,f)!=(size_t)length){fclose(f);free(src);return -6;}
 fclose(f);
 FILE *dst=fopen(output,"wb");if(!dst){free(src);return -7;}
 unsigned char head[44];memset(head,0,sizeof(head));memcpy(head,"RIFF",4);memcpy(head+8,"WAVEfmt ",8);
 mg_wr32(head+16,16);mg_wr16(head+20,1);memcpy(head+36,"data",4);
 if(fwrite(head,1,44,dst)!=44){fclose(dst);remove(output);free(src);return -8;}
 unsigned char *pkt=(unsigned char*)malloc(320000);OpusDecoder *dec=NULL;
 if(!pkt){fclose(dst);remove(output);free(src);return -9;}
 size_t cursor=0,psz=0;unsigned int packets=0,bytes=0;int channels=0;int skip=0;int fail=0;
 while(cursor<(size_t)length && fail==0){
  if(cursor+27>(size_t)length||memcmp(src+cursor,"OggS",4)!=0||src[cursor+4]!=0){fail=10;break;}
  unsigned nseg=src[cursor+26];if(cursor+27+nseg>(size_t)length){fail=11;break;}
  size_t bytesInPage=0;for(unsigned i=0;i<nseg;i++)bytesInPage+=src[cursor+27+i];
  size_t payload=cursor+27+nseg;if(payload+bytesInPage>(size_t)length){fail=12;break;}
  size_t at=payload;
  for(unsigned i=0;i<nseg && !fail;i++){
    unsigned count=src[cursor+27+i];if(psz+count>320000){fail=13;break;}
    memcpy(pkt+psz,src+at,count);at+=count;psz+=count;
    if(count==255)continue;
    packets++;
    if(packets==1){
      if(psz<19||memcmp(pkt,"OpusHead",8)!=0||pkt[8]!=1){fail=14;break;}
      channels=pkt[9];if(channels<1||channels>2){fail=15;break;}
      skip=(int)pkt[10]|((int)pkt[11]<<8);
      int status=0;dec=opus_decoder_create(48000,channels,&status);
      if(!dec||status!=OPUS_OK){fail=16;break;}
    }else if(packets==2){if(psz<8||memcmp(pkt,"OpusTags",8)!=0){fail=17;break;}}
    else {
      opus_int16 pcm[5760*2];int frames=opus_decode(dec,pkt,(opus_int32)psz,pcm,5760,0);
      if(frames<0){fail=18;break;}
      int trim=skip<frames?skip:frames;skip-=trim;frames-=trim;
      if(frames>0){size_t n=(size_t)frames*(size_t)channels*2u;
       if(bytes+n>24000000u || fwrite(pcm+(size_t)trim*(size_t)channels,1,n,dst)!=n){fail=19;break;}
       bytes+=(unsigned)n;
      }
    }
    psz=0;
  }
  cursor=payload+bytesInPage;
 }
 if(dec)opus_decoder_destroy(dec);
 free(pkt);free(src);
 if(fail || packets<3 || bytes==0){fclose(dst);remove(output);return fail? -fail:-20;}
 mg_wr32(head+4,36+bytes);mg_wr16(head+22,(unsigned)channels);mg_wr32(head+24,48000);
 mg_wr32(head+28,(unsigned)(48000*channels*2));mg_wr16(head+32,(unsigned)(channels*2));mg_wr16(head+34,16);mg_wr32(head+40,bytes);
 if(fseek(dst,0,SEEK_SET)!=0||fwrite(head,1,44,dst)!=44){fclose(dst);remove(output);return -21;}
 fclose(dst);return 0;
}
