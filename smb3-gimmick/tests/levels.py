#!/usr/bin/env python3
"""Write out/levels.txt: every level the world maps enter, and every area those lead to.

Each line is: name world tileset layout objects parent. Areas behind pipes and doors come
from the alternate layout and objects in their parent's header (src/PRG/levels/).
"""
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")


def parse_list(text, name):
    out = []
    for sfx in ("", "_S2", "_S3", "_S4"):
        m = re.search(r"^%s%s:\s*(?:\.(?:byte|word)\s+(.*))?$" % (name, sfx), text, re.M)
        if m and m.group(1):
            out += [s.strip() for s in m.group(1).split(",")]
    return out


def main():
    fns = {}
    for line in open(os.path.join(ROOT, "out", "smb3.fns")):
        m = re.match(r"^(\S+)\s+=\s+\$(\w+)", line)
        if m:
            fns[m.group(1)] = int(m.group(2), 16)

    # Layout label -> its file, from the banks that include them
    files = {}
    for bank in glob.glob(os.path.join(SRC, "PRG", "levels", "*.asm")):
        for line in open(bank, errors="replace"):
            m = re.match(r'^(\w+):\s+\.include "(PRG/levels/[^"]+)"', line)
            if m:
                files[m.group(1)] = m.group(2) + ".asm"

    def header(name):
        path = files.get(name)
        if not path:
            return None
        text = open(os.path.join(SRC, path), errors="replace").read()
        words = re.findall(r"\.word\s+(\S+)", text)[:2]
        ts = re.search(r"LEVEL3_TILESET_(\d+)", text)
        return words, int(ts.group(1)) if ts else None

    def val(s):
        return int(s[1:], 16) if s.startswith("$") else fns.get(s)

    lines, seen = [], set()

    def add(lay, obj, world, tileset, parent):
        if lay in seen or val(lay) is None or val(obj) is None:
            return
        seen.add(lay)
        lines.append((lay, world, tileset, val(lay), val(obj), parent))
        h = header(lay)
        if h and len(h[0]) == 2:
            (alay, aobj), ats = h
            if ats is not None and val(alay) not in (None, val(lay)) and alay in files:
                add(alay, aobj, world, ats, lay)

    for w in range(1, 9):
        text = open(os.path.join(SRC, "PRG", "maps", "World%dS.asm" % w)).read()
        rows = parse_list(text, "W%d_ByRowType" % w)
        objs = parse_list(text, "W%d_ObjSets" % w)
        lays = parse_list(text, "W%d_LevelLayout" % w)
        for r, o, l in zip(rows, objs, lays):
            if l.startswith("$"):
                continue
            add(l, o, w - 1, int(r[1:], 16) & 0x0F, "-")

    for w in range(1, 9):
        add("W%dAirshipL" % w, "W%dAirshipO" % w, w - 1, 10, "-")

    with open(os.path.join(ROOT, "out", "levels.txt"), "w") as f:
        for l in lines:
            f.write("%s %d %d %d %d %s\n" % l)
    print(len(lines), "areas")


main()
