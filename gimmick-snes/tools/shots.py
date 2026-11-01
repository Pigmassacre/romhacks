#!/usr/bin/env python3
"""Run a build in Mesen and take screenshots at given NMI counts.

    python3 tools/shots.py [--nes] 300 600 900    # out/shots/
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "shots") + "/"


def main():
    args = sys.argv[1:]
    nes = "--nes" in args
    args = [a for a in args if a != "--nes"]
    os.makedirs(OUT, exist_ok=True)
    script = OUT + ("nes" if nes else "snes") + ".lua"
    with open(script, "w") as f:
        f.write("OUT = %r\nSNES = %s\nAT = {%s}\n" % (OUT, "false" if nes else "true", ",".join(args)))
        f.write(open(os.path.join(REPO, "tests", "s_shots.lua")).read())
    rom = os.path.join(REPO, "Gimmick! (Japan).nes") if nes else os.path.join(REPO, "out", "gimmick.sfc")
    subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=200", rom, script], cwd=REPO, timeout=240,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
