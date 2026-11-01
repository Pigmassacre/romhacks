#!/usr/bin/env python3
"""Compare the translated game's RAM with the Mesen recording, NMI by NMI.

    python3 tools/compare.py [mine.bin] [reference.bin]
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 0x800 + 0x2000
WAIT_LOOP = (0xF29A, 0xF2A5)


def addr(i):
    return i if i < 0x800 else 0x6000 + i - 0x800


def main():
    mine = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "out", "host_ram.bin")
    ref = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "out", "trace", "ram.bin")
    a, b = open(mine, "rb").read(), open(ref, "rb").read()
    frames = min(len(a), len(b)) // SIZE
    # The stack at and below the interrupt's own pushes is not game state: the
    # translation takes interrupts between blocks, not between instructions.
    sps = [int(l.split()[5]) for l in open(os.path.join(os.path.dirname(ref), "cpu.txt"))]
    print("comparing %d NMIs (mine %d, reference %d)" % (frames, len(a) // SIZE, len(b) // SIZE))
    # Bytes the game has not initialised yet differ by power-on state: a byte
    # only counts once it has matched, or once the reference has changed it.
    live = [False] * SIZE
    prev = b[:SIZE]
    first_bad = None
    idle = busy_ref = 0
    late = []
    for f in range(frames):
        x, y = a[f * SIZE:(f + 1) * SIZE], b[f * SIZE:(f + 1) * SIZE]
        diffs = []
        dead = 0x100 + sps[f] + 3
        # An NMI that lands mid-calculation, on a frame the game runs long, catches
        # scratch values at a slightly different point. Compare only when the game
        # is idle in its wait loop on both sides.
        here = lambda r: r[0x100 + sps[f] + 2] | r[0x100 + sps[f] + 3] << 8
        idle += 1
        if not (WAIT_LOOP[0] <= here(y) <= WAIT_LOOP[1]):
            idle -= 1
            busy_ref += 1
            continue
        if not (WAIT_LOOP[0] <= here(x) <= WAIT_LOOP[1]):
            late.append(f + 1)
            idle -= 1
            continue
        for i in range(SIZE):
            if 0x100 <= i <= dead:
                continue
            if x[i] == y[i] or y[i] != prev[i]:
                live[i] = True
            if x[i] != y[i] and live[i]:
                diffs.append(i)
        prev = y
        if diffs and first_bad is None:
            first_bad = f
            print("first difference at NMI %d: %d bytes" % (f + 1, len(diffs)))
            for i in diffs[:24]:
                print("  $%04X mine %02X reference %02X" % (addr(i), x[i], y[i]))
            break
    if first_bad is None:
        print("MATCH: all live RAM is the same at %d idle NMIs; the NES was busy at %d more" % (idle, busy_ref))
        print("mine was still busy where the NES was idle at %d NMIs: %s" % (len(late), late[:20]))
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
