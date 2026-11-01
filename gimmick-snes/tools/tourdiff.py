#!/usr/bin/env python3
"""Compare nametables between the NES and SNES tours, checkpoint by checkpoint."""
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(REPO, "out", "tour")
for line in open(os.path.join(T, "nes", "marks.txt")):
    name = line.split()[1]
    a, b = [os.path.join(T, s, "nt_%s.bin" % name) for s in ("nes", "snes")]
    if not os.path.exists(b):
        continue
    n, s = open(a, "rb").read(), open(b, "rb").read()
    bad = [0, 0]
    pal = [0, 0]
    for page in (0, 1):
        for r in range(30):
            for c in range(32):
                t = n[page * 0x400 + r * 32 + c]
                w = s[page * 0x800 + (r * 32 + c) * 2:page * 0x800 + (r * 32 + c) * 2 + 2]
                if w[0] != t:
                    bad[page] += 1
                x = n[page * 0x400 + 0x3C0 + (r >> 2) * 8 + (c >> 2)]
                if (w[1] >> 2) & 7 != x >> (((r & 2) << 1) | (c & 2)) & 3:
                    pal[page] += 1
    st = [open(os.path.join(T, x, "st_%s.txt" % name)).read() for x in ("nes", "snes")]
    print("%-16s tiles %4d %4d  pal %4d %4d  %s | %s" % (name, bad[0], bad[1], pal[0], pal[1], st[0], st[1]))
