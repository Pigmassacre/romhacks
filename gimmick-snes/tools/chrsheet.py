#!/usr/bin/env python3
"""Draw CHR pages as a labelled tile sheet, to find tiles by eye.

    python3 tools/chrsheet.py out/sheet.png 00 01 02 2D
"""
import os
import sys
from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
chr_rom = open(os.path.join(REPO, "Gimmick! (Japan).nes"), "rb").read()[16 + 0x40000:]
pages = [int(p, 16) for p in sys.argv[2:]]
S = 3
im = Image.new("RGB", (len(pages) * (8 * 8 * S + 8 * 4 + 8), 8 * (8 * S + 10) + 8), (40, 40, 80))
d = ImageDraw.Draw(im)
COL = [(90, 140, 240), (70, 70, 70), (170, 170, 170), (255, 255, 255)]
for pi, p in enumerate(pages):
    for t in range(64):
        x0 = pi * (8 * 8 * S + 8 * 4 + 8) + (t % 8) * (8 * S + 4) + 4
        y0 = (t // 8) * (8 * S + 10) + 10
        d.text((x0, y0 - 10), "%02X" % (t + pi * 64 + (0)), fill=(255, 255, 0))
        off = p * 0x400 + t * 16
        for y in range(8):
            for x in range(8):
                v = (chr_rom[off + y] >> (7 - x) & 1) | (chr_rom[off + 8 + y] >> (7 - x) & 1) << 1
                d.rectangle([x0 + x * S, y0 + y * S, x0 + x * S + S - 1, y0 + y * S + S - 1], fill=COL[v])
im.save(sys.argv[1])
