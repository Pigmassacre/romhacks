#!/usr/bin/env python3
"""Compare the sound chips' state in Mesen with this port's model, frame by frame.

    APU_LOG=out/apu_mine.txt ./out/host "Gimmick! (Japan).nes" out/trace 6000 /dev/null
    python3 tools/compare_sound.py

Envelopes tick at slightly different moments in a frame here, so a value that matches
the frame before or after counts as a match.
"""
import os

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = ["pulse1 period", "pulse1 volume", "pulse1 duty", "pulse2 period", "pulse2 volume", "pulse2 duty",
         "triangle period", "triangle on", "noise period", "noise volume"] + ["5B reg %d" % i for i in range(14)]
a = np.loadtxt(os.path.join(REPO, "out", "apu_mine.txt"), dtype=int)
b = np.loadtxt(os.path.join(REPO, "out", "trace", "apu.txt"), dtype=int)
n = min(len(a), len(b)) - 2
print("%d frames" % n)
for i, name in enumerate(NAMES):
    x = a[1:n + 1, i]
    close = (x == b[1:n + 1, i]) | (x == b[0:n, i]) | (x == b[2:n + 2, i])
    bad = np.flatnonzero(~close)
    print("%-16s %6.2f%% match%s" % (name, 100 * close.mean(), "" if not len(bad) else
          ", first differs at %d: mine %d, Mesen %d" % (bad[0], x[bad[0]], b[bad[0] + 1, i])))
