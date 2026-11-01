#!/usr/bin/env python3
"""Compare the translated game's RAM with a Mesen recording, NMI by NMI.

    python3 tools/compare.py <trace-dir> <mine.bin>

An NMI that lands mid-calculation, on a frame the game runs long, catches scratch
values at a slightly different point, so only NMIs where the game is idle in its
wait loop are compared. The stack at and below the interrupt's own pushes is left
out: the translation takes interrupts between blocks, not between instructions.
"""
import os
import sys

import numpy as np

SIZE = 0x800 + 0x2000
WAIT_LOOP = (0xF29A, 0xF2A5)


def addr(i):
    return i if i < 0x800 else 0x6000 + i - 0x800


def main():
    trace, mine = sys.argv[1], sys.argv[2]
    ref = os.path.join(trace, "ram.bin")
    a = np.memmap(mine, dtype=np.uint8, mode="r")
    a = a[:len(a) // SIZE * SIZE].reshape(-1, SIZE)
    b = np.memmap(ref, dtype=np.uint8, mode="r").reshape(-1, SIZE)
    frames = min(len(a), len(b))
    sps = [int(l.split()[5]) for l in open(os.path.join(trace, "cpu.txt"))]
    print("comparing %d NMIs (mine %d, recording %d)" % (frames, len(a), len(b)))
    idle = busy = 0
    late = []
    for f in range(frames):
        x, y = a[f], b[f]
        at = 0x100 + sps[f]
        pc_y = int(y[at + 2]) | int(y[at + 3]) << 8
        pc_x = int(x[at + 2]) | int(x[at + 3]) << 8
        if not WAIT_LOOP[0] <= pc_y <= WAIT_LOOP[1]:
            busy += 1
            continue
        if not WAIT_LOOP[0] <= pc_x <= WAIT_LOOP[1]:
            late.append(f + 1)
            continue
        idle += 1
        d = np.flatnonzero(x != y)
        d = d[(d < 0x100) | (d > at + 3)]
        if len(d):
            print("first difference at NMI %d: %d bytes" % (f + 1, len(d)))
            for i in d[:24]:
                print("  $%04X mine %02X recording %02X" % (addr(int(i)), x[i], y[i]))
            return 1
    print("MATCH: all RAM is the same at %d idle NMIs; the NES was busy at %d more" % (idle, busy))
    print("mine was still busy where the NES was idle at %d NMIs: %s" % (len(late), late[:20]))
    return 0 if frames else 1


if __name__ == "__main__":
    sys.exit(main())
