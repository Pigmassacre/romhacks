#!/usr/bin/env python3
"""Where the SNES build's time goes in a scene, by routine.

    python3 tools/prof.py [scene] [frames] [--keep]    # out/lag/prof_<scene>.txt

The scenes are tools/lag.py's. It starts 120 frames in, or PROF_FROM frames in, and --keep only
adds up the last log again. PROF_TOP is how many routines to list for each part.

Each instruction's master clocks are logged in Mesen (tests/s_prof.lua); this adds them up
by the nearest label before them in src/ (out/gen/labels.txt), or by the game's own code,
32 bytes at a time, and by what they were part of: the NMI, the status bar's interrupt, the
game's frame before it is done, and the wait after. The first three are what a frame needs.
"""
import bisect
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lag

REPO = lag.REPO
PARTS = {"N": "NMI", "I": "interrupt", "W": "frame", "D": "done"}


def main():
    args = sys.argv[1:]
    scene = next((a for a in args if a in lag.SCENES), "crowd")
    nums = [a for a in args if a.isdigit()]
    frames = int(nums[0]) if nums else 120
    os.makedirs(lag.OUT, exist_ok=True)
    if "--keep" not in args:
        lag.run(True, scene, int(os.environ.get("PROF_FROM", 120)) - 120 + frames + 10, prof=frames)
    labels = []
    for line in open(os.path.join(lag.BUILD, "labels.txt") if lag.BUILD else os.path.join(REPO, "out", "gen", "labels.txt")):
        m = re.match(r"al 00([0-9A-F]{4}) \.([A-Za-z_]\w*)$", line.strip())
        if m:
            labels.append((int(m.group(1), 16), m.group(2)))
    labels.sort()
    addrs = [a for a, _ in labels]
    by, part = {}, {}
    for line in open(lag.OUT + "prof_" + scene + ".txt"):
        k, c = line.split()
        p, a, c = k[0], int(k[1:], 16), int(c)
        lo = a & 0xFFFF
        # RAM and bank 0's code are the port's; so is $C000-$DFFF in the game's banks.
        if lo < 0x2000 or (a >> 16) in (0, 0x80) or 0xC000 <= lo < 0xE000:
            i = bisect.bisect_right(addrs, lo) - 1
            name = labels[i][1] if i >= 0 else "?"
            if 0xC000 <= lo < 0xE000 and (a >> 16) not in (0, 0x80):
                name = "fast:" + name
        else:
            name = "game %04X" % (lo & 0xFFE0)
        part[p] = part.get(p, 0) + c
        by[(p, name)] = by.get((p, name), 0) + c
    frame = 357368.0 * frames    # master clocks
    print("%s, %d frames: %s" % (scene, frames, ", ".join("%s %.1f%%" % (PARTS[p], 100 * part.get(p, 0) / frame) for p in "NIWD")))
    need = sum(part.get(p, 0) for p in "NIW")
    print("a frame needs %.1f%% on average" % (100 * need / frame))
    for p in "NIWD":
        rows = sorted(((c, n) for (q, n), c in by.items() if q == p), reverse=True)
        print("\n%s:" % PARTS[p])
        for c, n in rows[:int(os.environ.get("PROF_TOP", "18"))]:
            print("  %5.2f%%  %s" % (100 * c / frame, n))


if __name__ == "__main__":
    main()
