#!/usr/bin/env python3
"""Make out/demo.gif from the frames tests/survey/s_demo.lua saves.

    python3 tests/run.py demo && python3 tools/demo_gif.py
"""
import glob
import os

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
frames = sorted(glob.glob(os.path.join(REPO, "out", "test", "demo_*.png")))
ims = [Image.open(p).convert("RGB").crop((0, 8, 256, 232)).resize((512, 448), Image.NEAREST) for p in frames]
pal = [im.quantize(colors=64, method=Image.MEDIANCUT) for im in ims]
out = os.path.join(REPO, "out", "demo.gif")
pal[0].save(out, save_all=True, append_images=pal[1:], duration=33, loop=0, optimize=True)
print("wrote %s (%d frames)" % (os.path.relpath(out, REPO), len(ims)))
