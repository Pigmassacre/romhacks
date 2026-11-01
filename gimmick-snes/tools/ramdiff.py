#!/usr/bin/env python3
"""Play both machines with the same buttons and find where their RAM first differs.

    python3 tools/ramdiff.py [frames]    # out/ramdiff/
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "ramdiff") + "/"
PICK = "PICK = function(f) return {start = f % 60 < 5} end\n" if "--start" in sys.argv else ""


def record(snes, frames):
    script = OUT + ("snes" if snes else "nes") + ".lua"
    with open(script, "w") as f:
        f.write("OUT = %r\nSNES = %s\nFRAMES = %d\n%s" % (OUT, "true" if snes else "false", frames, PICK))
        f.write(open(os.path.join(REPO, "tests", "s_ramlog.lua")).read())
    rom = os.path.join(REPO, "out", "gimmick.sfc") if snes else os.path.join(REPO, "Gimmick! (Japan).nes")
    subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=300", rom, script], cwd=REPO, timeout=330,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    frames = int(args[0]) if args else 400
    os.makedirs(OUT, exist_ok=True)
    if not os.path.exists(OUT + "nes.bin") or os.path.getsize(OUT + "nes.bin") != frames * 0x800:
        record(False, frames)
    record(True, frames)
    a = open(OUT + "nes.bin", "rb").read()
    b = open(OUT + "snes.bin", "rb").read()
    print("NMIs: nes %d, snes %d" % (len(a) // 0x800, len(b) // 0x800))
    # The game counts the frames it finishes at $ED, $EE: line them up by that.
    def by_count(d):
        out = {}
        for n in range(len(d) // 0x800):
            r = d[n * 0x800:(n + 1) * 0x800]
            if r[0xF0] == 0xAC:
                out.setdefault(r[0xED] | r[0xEE] << 8, []).append(r)
        return out
    na, nb = by_count(a), by_count(b)
    shown = 0
    for c in sorted(set(na) & set(nb)):
        x, y = na[c][0], nb[c][0]
        diffs = [i for i in range(0x800) if x[i] != y[i] and not 0x100 <= i < 0x170 and not 0x190 <= i < 0x200
                 and not 0x56 <= i < 0x80 and not i >= 0x600]    # the sound driver counts all NMIs
        if diffs:
            print("frame %d: %d bytes differ" % (c, len(diffs)))
            for i in diffs[:24]:
                print("  $%04X nes %02X snes %02X" % (i, x[i], y[i]))
            return
    print("the same to the end")


if __name__ == "__main__":
    main()
