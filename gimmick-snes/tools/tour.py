#!/usr/bin/env python3
"""Tour the whole game on the NES, the SNES build or both, with screenshots, and put
pairs side by side.

    python3 tools/tour.py [--nes] [--snes] [--play N]    # out/tour/
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "tour") + "/"


def run(snes, play):
    out = OUT + ("snes/" if snes else "nes/")
    os.makedirs(out, exist_ok=True)
    script = out + "tour.lua"
    open(out + "marks.txt", "w").close()
    with open(script, "w") as f:
        f.write("OUT = %r\nSNES = %s\nSHOTS = true\nPLAY = %d\nDUMP_ALL = %r\n" % (out, "true" if snes else "false", play, os.environ.get("DUMP_ALL", "")))
        f.write(open(os.path.join(REPO, "tests", "s_tourshots.lua")).read())
        f.write(open(os.path.join(REPO, "tests", "s_tour.lua")).read())
    rom = os.path.join(REPO, "out", "gimmick.sfc") if snes else os.path.join(REPO, "Gimmick! (Japan).nes")
    subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=500", rom, script], cwd=REPO, timeout=530,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    args = sys.argv[1:]
    play = int(args[args.index("--play") + 1]) if "--play" in args else 500
    both = "--nes" not in args and "--snes" not in args
    if both or "--nes" in args:
        run(False, play)
    if both or "--snes" in args:
        run(True, play)


if __name__ == "__main__":
    main()
