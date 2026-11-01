#!/usr/bin/env python3
"""Pair up tour screenshots: out/tour/m_<n>.png, 6 pairs a page."""
import os
import sys
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(REPO, "out", "tour")
names = [l.split()[1] for l in open(os.path.join(T, "nes", "marks.txt"))]
names = [n for n in names if os.path.exists(os.path.join(T, "snes", "shot_%s.png" % n))]
if len(sys.argv) > 1:
    names = [n for n in names if any(a in n for a in sys.argv[1:])]
for page in range(0, len(names), 12):
    part = names[page:page + 12]
    m = Image.new("RGB", (256 * 4, 484 * ((len(part) + 3) // 4)), (255, 0, 0))
    for i, n in enumerate(part):
        for k, side in enumerate(("nes", "snes")):
            m.paste(Image.open(os.path.join(T, side, "shot_%s.png" % n)), (256 * (i % 4), 484 * (i // 4) + 240 * k))
    m.save(os.path.join(T, "m_%d.png" % (page // 12)))
print(len(names), "pairs")
print(names)
