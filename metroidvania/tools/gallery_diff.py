#!/usr/bin/env python3
"""Compare tests/s_gallery.lua's screenshots from the two ROMs: which sprite poses
look different in the hack. Writes out/test/gallery_diff.png, original over hack."""
import glob
import os

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out", "test")
# The screen split into the poses' four places (see s_gallery.lua's AT); Simon or
# Samus stands below these, and the HUD is above them.
AREAS = [(0, 56, 128, 112), (128, 56, 256, 112), (0, 112, 128, 160), (128, 112, 256, 160)]
pairs = []
for hack in sorted(glob.glob(os.path.join(OUT, "gallery_hack_*.png"))):
    pose = int(hack[-6:-4], 16)
    orig = hack.replace("_hack_", "_orig_")
    a, b = Image.open(orig).convert("RGB"), Image.open(hack).convert("RGB")
    for k, box in enumerate(AREAS):
        ca, cb = a.crop(box), b.crop(box)
        if ca.tobytes() != cb.tobytes():
            pairs.append((pose + k, ca, cb))
print("poses that differ:", " ".join("%02x" % p[0] for p in pairs))
if pairs:
    w, h = 128, 56
    cols = 6
    rows = (len(pairs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * (h * 2 + 2)), (255, 0, 255))
    for i, (p, ca, cb) in enumerate(pairs):
        x, y = (i % cols) * w, (i // cols) * (h * 2 + 2)
        sheet.paste(ca, (x, y))
        sheet.paste(cb, (x, y + h))
    sheet.save(os.path.join(OUT, "gallery_diff.png"))
