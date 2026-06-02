#!/usr/bin/env python3
# arbscan - read the OEM anti-rollback (ARB) index from a Qualcomm xbl/xbl_config ELF.
# Port of the technique from github.com/syedinsaf/arbscan (credit to the original).
# Usage: arbscan.py <xbl_or_xbl_config.img> [more.img ...]
#   prints:  <file>  OEM ver A.B   ARB index = N
import sys, struct
HASH_HDR=36; SCAN_MAX=0x1000; MAXSEG=20*1024*1024
def u16(b,o): return struct.unpack_from('<H',b,o)[0]
def u32(b,o): return struct.unpack_from('<I',b,o)[0]
def u64(b,o): return struct.unpack_from('<Q',b,o)[0]
def find_hdr(seg):
    for off in range(0,min(SCAN_MAX,len(seg)),4):
        if off+HASH_HDR>len(seg): break
        ver=u32(seg,off); cs=u32(seg,off+4); qs=u32(seg,off+8); os=u32(seg,off+12); hts=u32(seg,off+16)
        if not(1<=ver<=10): continue
        if cs>0x1000 or qs>0x1000 or os>0x4000: continue
        if hts==0 or (hts&0x1F)!=0: continue
        if off+HASH_HDR+cs+qs+os>len(seg): continue
        return off
    return None
def scan(path):
    d=open(path,'rb').read()
    if d[:4]!=b'\x7fELF' or d[4]!=2 or d[5]!=1: return ('not ELF64LE',)
    e_phoff=u64(d,0x20); e_phentsz=u16(d,0x36); e_phnum=u16(d,0x38); fsz=len(d)
    for i in range(e_phnum):
        o=e_phoff+i*e_phentsz; ph=d[o:o+e_phentsz]
        if len(ph)<40: continue
        p_flags=u32(ph,4); p_offset=u64(ph,8); p_filesz=u64(ph,32)
        if p_filesz==0 or p_offset+p_filesz>fsz: continue
        if (p_flags&1)==0 and HASH_HDR<=p_filesz<=MAXSEG:
            seg=d[p_offset:p_offset+p_filesz]; hdr=find_hdr(seg)
            if hdr is None: continue
            cs=u32(seg,hdr+4); qs=u32(seg,hdr+8); om=hdr+HASH_HDR+cs+qs
            if om+12>len(seg): continue
            major=u32(seg,om); minor=u32(seg,om+4); arb=u32(seg,om+8)
            if major<1000 and minor<1000 and arb<128: return (major,minor,arb)
    return ('no OEM metadata found',)
if len(sys.argv)<2:
    print("usage: arbscan.py <xbl_or_xbl_config.img> [...]"); sys.exit(2)
worst=0
for p in sys.argv[1:]:
    r=scan(p)
    if len(r)==3:
        print(f"{p:40} OEM ver {r[0]}.{r[1]}   ARB index = {r[2]}"); worst=max(worst,r[2])
    else:
        print(f"{p:40} {r[0]}")
print(f"\nHighest ARB index seen: {worst}")
