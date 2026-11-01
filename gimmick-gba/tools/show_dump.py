#!/usr/bin/env python3
"""Draw out/video_dump.bin the way the NES would, as a PPM, with no GBA code.

    DUMP_FRAME=2400 ./out/host ...; python3 tools/show_dump.py out/video.ppm
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d = open(os.path.join(REPO, "out", "video_dump.bin"), "rb").read()
ciram, pal, oam = d[:0x800], d[0x800:0x820], d[0x820:0x920]
top_chr, cur_chr = d[0x920:0x928], d[0x928:0x930]
m = d[0x930:]
top_t, top_x, ctrl = m[0] | m[1] << 8, m[2], m[3]
split = m[4] | m[5] << 8
mirror = m[8]
print("t=%04X x=%d ctrl=%02X split=%d t2=%04X mirror=%d mask=%02X chr=%s now=%s" % (
    top_t, top_x, ctrl, split, m[6] | m[7] << 8, mirror, m[9], top_chr.hex(), cur_chr.hex()))
chrr = open(os.path.join(REPO, "Gimmick! (Japan).nes"), "rb").read()[16 + 0x40000:]


def idx(a):
    a &= 0xFFF
    if mirror & 3 == 0:
        return a & 0x7FF
    if mirror & 3 == 1:
        return (a & 0x3FF) | (a >> 1 & 0x400)
    return (a & 0x3FF) | ((mirror & 1) << 10)


bg = 4 if ctrl & 0x10 else 0
out = bytearray(512 * 480 * 3)
G = [(v * 85) for v in range(4)]
for nty in range(2):
    for ntx in range(2):
        base = 0x2000 + (nty << 11) + (ntx << 10)
        for r in range(30):
            for c in range(32):
                tile = ciram[idx(base + r * 32 + c)]
                page = top_chr[bg + (tile >> 6)]
                at = page * 0x400 + (tile & 63) * 16
                for y in range(8):
                    lo, hi = chrr[at + y], chrr[at + 8 + y]
                    for x in range(8):
                        p = (lo >> (7 - x) & 1) | (hi >> (7 - x) & 1) << 1
                        o = ((nty * 240 + r * 8 + y) * 512 + ntx * 256 + c * 8 + x) * 3
                        out[o:o + 3] = bytes([G[p]] * 3)
open(sys.argv[1], "wb").write(b"P6 512 480 255\n" + out)
