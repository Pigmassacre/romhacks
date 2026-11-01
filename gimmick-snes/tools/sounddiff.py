#!/usr/bin/env python3
"""Play both machines and compare each sound channel, NMI by NMI: is the DSP voice on when
the NES channel is, at the right pitch and a proportional volume?

    python3 tools/sounddiff.py [frames]    # out/ramdiff/
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "ramdiff") + "/"
FRAMES = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
NAMES = ["pulse 1", "pulse 2", "triangle", "noise", "dpcm", "5B A", "5B B", "5B C"]


def record(snes):
    os.makedirs(OUT, exist_ok=True)
    script = OUT + "snd.lua"
    with open(script, "w") as f:
        f.write("OUT = %r\nSNES = %s\nFRAMES = %d\n" % (OUT, "true" if snes else "false", FRAMES))
        f.write(open(os.path.join(REPO, "tests", "s_sndlog.lua")).read())
    rom = os.path.join(REPO, "out", "gimmick.sfc") if snes else os.path.join(REPO, "Gimmick! (Japan).nes")
    subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=300", rom, script], cwd=REPO, timeout=330,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def load(name):
    rows = []
    for line in open(OUT + name):
        f = line.split()
        rows.append([tuple(int(x) for x in c.split(",")) for c in f[1:9]] + [int(f[9])])
    return rows


def want_pitch(ch, per):
    return min(229090 // (per + 1 if ch < 5 else max(per, 1)), 0x3FFF)


def score(a, b, off):
    s = 0
    for i in range(200, min(len(a), len(b)) - 60, 2):
        j = i + off
        if 0 <= j < len(b):
            for ch in (0, 1, 2, 5, 6, 7):
                x, y = a[i][ch], b[j][ch]
                if x[0] and y[0] and abs(want_pitch(ch, x[1]) - y[1]) <= max(2, y[1] // 50):
                    s += 1
    return s


def main():
    if "--again" not in sys.argv:
        record(False)
        record(True)
    a, b = load("snd_nes.txt"), load("snd_snes.txt")
    off = max(range(-40, 41), key=lambda o: score(a, b, o))
    print("NMIs %d/%d, best line-up: SNES %+d" % (len(a), len(b), off))
    for ch in range(8):
        on_a = on_b = both = pitch_ok = vol_ok = 0
        worst = 0
        for i in range(len(a)):
            j = i + off
            if not 0 <= j < len(b):
                continue
            x, y = a[i][ch], b[j][ch]
            if x[0]:
                on_a += 1
            if y[0]:
                on_b += 1
            if x[0] and y[0]:
                both += 1
                if ch in (3, 4):
                    pitch_ok += 1
                else:
                    want = want_pitch(ch, x[1])
                    if abs(want - y[1]) <= max(2, want // 50):
                        pitch_ok += 1
                    else:
                        worst += 1
                if ch < 2 or ch == 3:
                    if (x[0] * (3 if ch < 2 else 2)) == y[0]:
                        vol_ok += 1
                else:
                    vol_ok += 1
        print("%-9s on: NES %5d SNES %5d both %5d  pitch ok %5d  volume ok %5d" % (NAMES[ch], on_a, on_b, both, pitch_ok, vol_ok))
    if "--show" in sys.argv:
        for ch in (0, 2, 7):
            show(a, b, off, ch)


def show(a, b, off, ch, n=8):
    shown = 0
    for i in range(300, len(a)):
        j = i + off
        if 0 <= j < len(b):
            x, y = a[i][ch], b[j][ch]
            if x[0] and y[0] and abs(want_pitch(ch, x[1]) - y[1]) > max(2, y[1] // 50):
                print(" ", NAMES[ch], "nmi", i, "nes", x, "want", want_pitch(ch, x[1]), "snes", y)
                shown += 1
                if shown >= n:
                    return


if __name__ == "__main__":
    main()
