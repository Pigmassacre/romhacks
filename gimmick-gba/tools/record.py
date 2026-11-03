#!/usr/bin/env python3
"""Record a run of the NES game in Mesen, for the translator and the checks.

    python3 tools/record.py [frames] [trace-from trace-to]    # out/trace/
    python3 tools/record.py --idle [frames]                   # out/trace_idle/
    python3 tools/record.py --tour                            # out/trace_tour/
    python3 tools/record.py --boss [frames]                   # out/trace_boss/
    python3 tools/record.py --15 [frames]                     # out/ref15/
    python3 tools/record.py --audio [frames]                  # out/audio_ref/

The default run plays stage 1 from the title. The trace logs every instruction
between two NMIs into steps.txt, for tools/stepdiff.py. --idle presses nothing, so
the translator also sees what the title screen leads to. --tour warps through the
whole game (tests/s_tour.lua). --boss fights the first stage's boss, the heaviest
frames (tests/s_boss.lua). --15 plays like the default on the NES game with all of
Gimmick! 1.5's features on (out/gen/gimmick-1.5.nes, which tools/recomp.py writes), as
a reference for the options; its code is not the game's, so its directory is not a
trace* that tools/freeze_coverage.py reads. --audio plays like the default but logs each sound
channel's output, for tools/compare_sound.py, and is much slower.
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
mode = "plain"
for name in ("idle", "tour", "boss", "15", "audio"):
    if "--" + name in args:
        args.remove("--" + name)
        mode = name
OUT = os.path.join(REPO, "out", {"plain": "trace", "idle": "trace_idle", "tour": "trace_tour", "boss": "trace_boss", "15": "ref15", "audio": "audio_ref"}[mode]) + "/"
os.makedirs(OUT, exist_ok=True)
frames = int(args[0]) if args else 3000
script = os.path.join(OUT, "record.lua")
with open(script, "w") as f:
    f.write("OUT = %r\nFRAMES = %d\n" % (OUT, frames))
    if mode == "idle":
        f.write("IDLE = true\n")
    if mode == "plain":
        f.write("APU_LOG = true\n")
    if mode == "audio":
        f.write("AUDIO_LOG = true\n")
    if len(args) > 2:
        f.write("TRACE_FROM = %s\nTRACE_TO = %s\n" % (args[1], args[2]))
    if mode in ("tour", "boss"):
        f.write(open(os.path.join(REPO, "tests", "s_" + mode + ".lua")).read())
    f.write(open(os.path.join(REPO, "tests", "s_record.lua")).read())
subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=1700",
                os.path.join(REPO, "out", "gen", "gimmick-1.5.nes") if mode == "15" else os.path.join(REPO, "Gimmick! (Japan).nes"),
                script], cwd=REPO, timeout=1750,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
