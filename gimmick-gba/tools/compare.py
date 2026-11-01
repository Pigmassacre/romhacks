#!/usr/bin/env python3
"""Compare the translated game's RAM with a Mesen recording, NMI by NMI.

    python3 tools/compare.py <trace-dir> <mine.bin>

The replay takes each NMI at the instruction the recording took it, so every byte
should match, on busy frames too. The stack page is left out: an IRQ's return address
can differ by an instruction in the game's wait loop, and it leads to the same place.
"""
import os
import sys

import numpy as np

SIZE = 0x800 + 0x2000


def addr(i):
    return i if i < 0x800 else 0x6000 + i - 0x800


def main():
    trace, mine = sys.argv[1], sys.argv[2]
    ref = os.path.join(trace, "ram.bin")
    a = np.memmap(mine, dtype=np.uint8, mode="r")
    a = a[:len(a) // SIZE * SIZE].reshape(-1, SIZE)
    b = np.memmap(ref, dtype=np.uint8, mode="r").reshape(-1, SIZE)
    frames = min(len(a), len(b))
    print("comparing %d NMIs (mine %d, recording %d)" % (frames, len(a), len(b)))
    for f in range(frames):
        x, y = a[f], b[f]
        d = np.flatnonzero(x != y)
        d = d[(d < 0x100) | (d >= 0x200)]
        if len(d):
            print("first difference at NMI %d: %d bytes" % (f + 1, len(d)))
            for i in d[:24]:
                print("  $%04X mine %02X recording %02X" % (addr(int(i)), x[i], y[i]))
            return 1
    print("MATCH: all RAM is the same at every one of the %d NMIs" % frames)
    return 0 if frames else 1


if __name__ == "__main__":
    sys.exit(main())
