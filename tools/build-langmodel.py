#!/usr/bin/env python3
"""สร้างโมเดลสถิติตัวอักษร (trigram) ไทย/อังกฤษ สำหรับ Convert Layout ของ Deft

    ./tools/build-langmodel.py <thai word-freq file> <english word-freq file> <output .bin>

ไฟล์คำ: บรรทัดละ "<คำ>\\t<ความถี่>" (ความถี่ไม่มี = 1)
  ไทย    : tnc_freq.txt จาก PyThaiNLP (Thai National Corpus, Apache-2.0)
  อังกฤษ : count_1w.txt ของ Peter Norvig (Google Web Trillion Word Corpus, ใช้ได้เสรี)

ผลลัพธ์ (little-endian):
  "DFLM" u8 version=1 u8 langs=2
  ต่อภาษา: u8 tag('t'|'e') f32 total  u32 nUni [u16 code f32 w]*  u32 nBi [u32 key f32 w]*  u32 nTri [u64 key f32 w]*
  key: bigram = a<<16|b, trigram = a<<32|b<<16|c   ·  code 1 = ขอบต้น/ท้ายคำ
น้ำหนักต่อคำ = 1 + ln(ความถี่) เพื่อไม่ให้คำที่พบบ่อยสุดกลบทุกอย่าง
"""
import math, struct, sys
from collections import defaultdict

BOUND = 1

def thai_code(ch):
    o = ord(ch)
    return o if 0x0E01 <= o <= 0x0E5B else None

def en_code(ch):
    if 'a' <= ch <= 'z': return ord(ch)
    if ch == "'": return ord("'")
    return None

def build(path, coder):
    uni, bi, tri = defaultdict(float), defaultdict(float), defaultdict(float)
    total = 0.0
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            word = parts[0].strip().lower()
            freq = float(parts[1]) if len(parts) > 1 and parts[1].strip() else 1.0
            codes = [coder(c) for c in word]
            if not codes or any(c is None for c in codes) or len(codes) > 40:
                continue
            w = 1.0 + math.log(max(freq, 1.0))
            seq = [BOUND, BOUND] + codes + [BOUND]
            for c in codes:
                uni[c] += w; total += w
            for i in range(1, len(seq)):
                bi[(seq[i-1] << 16) | seq[i]] += w
            for i in range(2, len(seq)):
                tri[(seq[i-2] << 32) | (seq[i-1] << 16) | seq[i]] += w
    return total, uni, bi, tri

def emit(out, tag, total, uni, bi, tri):
    out += struct.pack('<Bf', ord(tag), total)
    out += struct.pack('<I', len(uni))
    for k in sorted(uni): out += struct.pack('<Hf', k, uni[k])
    out += struct.pack('<I', len(bi))
    for k in sorted(bi): out += struct.pack('<If', k, bi[k])
    out += struct.pack('<I', len(tri))
    for k in sorted(tri): out += struct.pack('<Qf', k, tri[k])
    return out

def main():
    th_path, en_path, out_path = sys.argv[1:4]
    th = build(th_path, thai_code)
    en = build(en_path, en_code)
    out = b'DFLM' + struct.pack('<BB', 1, 2)
    out = emit(out, 't', *th)
    out = emit(out, 'e', *en)
    with open(out_path, 'wb') as f: f.write(out)
    print(f"thai: uni={len(th[1])} bi={len(th[2])} tri={len(th[3])}   english: uni={len(en[1])} bi={len(en[2])} tri={len(en[3])}   -> {len(out)/1024:.0f} KB")

if __name__ == '__main__':
    main()
