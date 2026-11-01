#!/usr/bin/env python3
"""Find the first block where the translated game and Mesen disagree.

    python3 tools/stepdiff.py out/host_steps.txt out/trace/steps.txt

The host logs each block's entry; Mesen logs each instruction, so the host's
lines must appear in Mesen's log in order, with the same registers.
"""
import sys

# The first line is the NMI entry itself, which Mesen logs before the count moves.
mine = [l.split() for l in open(sys.argv[1])][1:]
ref = [l.split() for l in open(sys.argv[2])]
j = 0
for i, m in enumerate(mine):
    k = j
    while k < len(ref) and ref[k][0] != m[0]:
        k += 1
    if k == len(ref) or ref[k] != m:
        print("block %d of mine differs: mine %s" % (i, " ".join(m)))
        print("reference at that point:")
        for r in ref[max(0, j - 12):j + 8]:
            print("  " + " ".join(r))
        print("mine before it:")
        for r in mine[max(0, i - 6):i + 1]:
            print("  " + " ".join(r))
        sys.exit(1)
    j = k + 1
print("all %d blocks match" % len(mine))
