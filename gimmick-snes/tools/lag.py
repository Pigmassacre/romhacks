#!/usr/bin/env python3
"""Count the frames the game loses, in busy scenes, on the NES and the SNES build.

    python3 tools/lag.py [--nes] [--snes] [scenes] [frames]    # out/lag/

A frame is lost when the NMI comes before the game has finished it. Two or more in a row are
the game's own loads; one alone is slowdown. On the SNES it also shows how many lines of the
frame the work took, from the start of vblank to the line where the game said it was done.
The scenes are crowd and boss, the first boss throwing with nothing pressed and fought, and
s<stage>_c<checkpoint>, played from each checkpoint; all is every one of them, and the default
crowd and boss. Yumetaro cannot die. LAG_ROM=<dir> measures the gimmick.sfc and labels.txt
there instead, into <dir>/lag/, and SHOT_AT=<n>,<n> takes screenshots at those frames.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "lag") + "/"
# name: stage, checkpoint, boss room (B8, A4) or None, buttons pressed
SCENES = {
    "crowd": (0, 3, (0x14, 0x33), False),   # the first boss throwing, standing still
    "boss": (0, 3, (0x14, 0x33), True),     # fighting it
}
for st in range(7):
    for cp in range(4):
        SCENES["s%d_c%d" % (st, cp)] = (st, cp, None, True)

BUILD = os.environ.get("LAG_ROM")
if BUILD:
    OUT = os.path.join(BUILD, "lag") + "/"


def label(name):
    for line in open(os.path.join(BUILD, "labels.txt") if BUILD else os.path.join(REPO, "out", "gen", "labels.txt")):
        m = re.match(r"al 00([0-9A-F]{4}) \.(\w+)$", line.strip())
        if m and m.group(2) == name:
            return int(m.group(1), 16)
    raise SystemExit("no %s in out/gen/labels.txt: build first" % name)


def run(snes, scene, frames, prof=0):
    st, cp, boss, move = SCENES[scene]
    script = OUT + ("snes" if snes else "nes") + "_" + scene + ".lua"
    with open(script, "w") as f:
        f.write("OUT = %r\nSNES = %s\nSCENE = %r\nSTAGE = %d\nCP = %d\nFRAMES = %d\nMOVE = %s\nFRAME_DONE = %d\n"
                % (OUT, "true" if snes else "false", scene, st, cp, frames, "true" if move else "false",
                   label("frame_done") if snes else 0))
        shots = os.environ.get("SHOT_AT")
        if shots:
            f.write("SHOT_AT = {%s}\n" % ",".join("[%s] = true" % n for n in shots.split(",")))
        if boss:
            f.write("BOSS = {%d, %d}\n" % boss)
        f.write(open(os.path.join(REPO, "tests", "s_lag.lua")).read())
        if prof:
            if os.environ.get("PROF_FROM"):
                f.write("PROF_FROM = %d\n" % int(os.environ["PROF_FROM"]))
            f.write("PROF_FRAMES = %d\nNMI_EMU = %d\nIRQ_EMU = %d\n" % (prof, label("nmi_emu"), label("irq_emu")))
            f.write(open(os.path.join(REPO, "tests", "s_prof.lua")).read())
    if not snes:
        rom = os.path.join(REPO, "Gimmick! (Japan).nes")
    else:
        rom = os.path.join(BUILD, "gimmick.sfc") if BUILD else os.path.join(REPO, "out", "gimmick.sfc")
    subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=%d" % (1700 if prof else 300), rom, script],
                   cwd=REPO, timeout=1800 if prof else 330, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    rows = [list(map(int, l.split()[:3])) for l in open(OUT + ("snes" if snes else "nes") + "_" + scene + ".txt")]
    return rows


def main():
    args = sys.argv[1:]
    machines = [m for m in (False, True) if ("--snes" if m else "--nes") in args] or [False, True]
    names = list(SCENES) if "all" in args else [a for a in args if a in SCENES] or ["crowd", "boss"]
    nums = [a for a in args if a.isdigit()]
    frames = int(nums[0]) if nums else 1200
    os.makedirs(OUT, exist_ok=True)
    for scene in names:
        for snes in machines:
            rows = run(snes, scene, frames)
            lost = sum(1 for r in rows if not r[1])
            # Runs of 2 or more are loads, as the game draws a new room: one alone is slowdown.
            runs, n = [], 0
            for r in rows + [[0, 1, 0]]:
                if not r[1]:
                    n += 1
                elif n:
                    runs.append(n)
                    n = 0
            slow = sum(n for n in runs if n == 1)
            line = "%-6s %-5s lost %4d of %4d, %3d in slowdown" % (scene, "snes" if snes else "nes", lost, len(rows), slow)
            if snes:
                # Lines of work from vblank's start at 225, to where frame_done was reached.
                used = sorted((r[2] - 225) % 262 for r in rows if r[2] >= 0)
                if used:
                    line += "   work in lines: median %d, 90%% %d, max %d (of 262)" % (
                        used[len(used) // 2], used[len(used) * 9 // 10], used[-1])
            print(line, flush=True)


if __name__ == "__main__":
    main()
