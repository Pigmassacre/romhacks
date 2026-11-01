#!/usr/bin/env python3
"""Put NES and SNES screenshots from tools/shots.py side by side: out/shots/m.png"""
import os
import sys
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AT = [int(a) for a in sys.argv[1:]]
m = Image.new("RGB", (256 * 4, (484) * ((len(AT) + 3) // 4)), (255, 0, 0))
for i, n in enumerate(AT):
    for k, p in enumerate(("nes", "snes")):
        f = os.path.join(REPO, "out", "shots", "%s_%06d.png" % (p, n))
        if os.path.exists(f):
            m.paste(Image.open(f), (256 * (i % 4), 484 * (i // 4) + 240 * k))
m.save(os.path.join(REPO, "out", "shots", "m.png"))
