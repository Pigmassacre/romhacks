#!/usr/bin/env python3
"""Play both machines to the same game frame and compare nametables with the SNES map.

    python3 tools/ntdiff.py 600    # out/ramdiff/
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "ramdiff") + "/"
COUNT = int(sys.argv[1]) if len(sys.argv) > 1 else 600
os.makedirs(OUT, exist_ok=True)
for snes in (False, True):
    script = OUT + "nt.lua"
    with open(script, "w") as f:
        f.write("OUT = %r\nSNES = %s\nCOUNT = %d\n" % (OUT, "true" if snes else "false", COUNT))
        f.write(open(os.path.join(REPO, "tests", "s_nt.lua")).read())
    rom = os.path.join(REPO, "out", "gimmick.sfc") if snes else os.path.join(REPO, "Gimmick! (Japan).nes")
    subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=200", rom, script], cwd=REPO, timeout=230,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
n = open(OUT + "nes_nt.bin", "rb").read()
s = open(OUT + "snes_nt.bin", "rb").read()
print(open(OUT + "nes_st.txt").read().strip())
print(open(OUT + "snes_st.txt").read().strip())
for page, name in ((0, "A"), (1, "B")):
    bad = []
    pal_bad = 0
    for r in range(30):
        for c in range(32):
            t = n[page * 0x400 + r * 32 + c]
            w = s[page * 0x800 + (r * 32 + c) * 2:page * 0x800 + (r * 32 + c) * 2 + 2]
            if w[0] != t:
                bad.append((r, c, t, w[0]))
            a = n[page * 0x400 + 0x3C0 + (r >> 2) * 8 + (c >> 2)]
            pal = a >> (((r & 2) << 1) | (c & 2)) & 3
            if (w[1] >> 2) & 7 != pal:
                pal_bad += 1
    print("map %s: %d tiles differ, %d palettes" % (name, len(bad), pal_bad))
    cols = {}
    for r, c, t, v in bad:
        cols.setdefault(c, []).append(r)
    print(" columns:", {c: (min(v), max(v), len(v)) for c, v in sorted(cols.items())})
    print(" first:", ["r%d c%d %02X/%02X" % x for x in bad[:10]])
