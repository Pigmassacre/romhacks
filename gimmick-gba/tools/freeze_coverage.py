#!/usr/bin/env python3
"""Merge the recordings in out/trace*/ into data/, which the translator reads.

    python3 tools/freeze_coverage.py

The files hold addresses and how often they ran: nothing of the game itself.
"""
import glob
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(REPO, "data")
BANK = 0x2000
PRG = 0x40000

# What runs in the busiest frames matters most, as that is where the GBA can fall
# behind, so the boss fight's recording counts for more when picking what goes in
# fast RAM.
WEIGHT = {"trace_boss": 20}

counts, entries = {}, set()
for trace in sorted(glob.glob(os.path.join(REPO, "out", "trace*"))):
    weight = WEIGHT.get(os.path.basename(trace), 1)
    for line in open(os.path.join(trace, "coverage.txt")):
        off, pc, n = map(int, line.split())
        if pc >= 0x8000 and 0 <= off < PRG:
            key = (off // BANK, pc)
            counts[key] = counts.get(key, 0) + n * weight
    for line in open(os.path.join(trace, "entries.txt")):
        entries.add(int(line))
os.makedirs(DATA, exist_ok=True)
with open(os.path.join(DATA, "coverage.txt"), "w") as f:
    for (num, pc), n in sorted(counts.items()):
        f.write("%02X %04X %d\n" % (num, pc, n))
with open(os.path.join(DATA, "entries.txt"), "w") as f:
    for a in sorted(entries):
        f.write("%04X\n" % a)
print("%d addresses, %d entry points" % (len(counts), len(entries)))
