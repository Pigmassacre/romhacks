#!/usr/bin/env python3
"""Record a run of the NES game in Mesen, for the translator and the checks.

    python3 tools/record.py [frames] [trace-from trace-to]    # out/trace/
    python3 tools/record.py --idle [frames]                   # out/trace_idle/
    python3 tools/record.py --tour                            # out/trace_tour/

The default run plays stage 1 from the title. The trace logs every instruction
between two NMIs into steps.txt, for tools/stepdiff.py. --idle presses nothing, so
the translator also sees what the title screen leads to. --tour warps through the
whole game (tests/s_tour.lua).
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
mode = "plain"
for name in ("idle", "tour"):
    if "--" + name in args:
        args.remove("--" + name)
        mode = name
OUT = os.path.join(REPO, "out", {"plain": "trace", "idle": "trace_idle", "tour": "trace_tour"}[mode]) + "/"
os.makedirs(OUT, exist_ok=True)
frames = int(args[0]) if args else 3000
script = os.path.join(OUT, "record.lua")
with open(script, "w") as f:
    f.write("OUT = %r\nFRAMES = %d\n" % (OUT, frames))
    if mode == "idle":
        f.write("IDLE = true\n")
    if mode == "plain":
        f.write("APU_LOG = true\n")
    if len(args) > 2:
        f.write("TRACE_FROM = %s\nTRACE_TO = %s\n" % (args[1], args[2]))
    if mode == "tour":
        f.write(open(os.path.join(REPO, "tests", "s_tour.lua")).read())
    f.write(open(os.path.join(REPO, "tests", "s_record.lua")).read())
subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=1700",
                os.path.join(REPO, "Gimmick! (Japan).nes"), script], cwd=REPO, timeout=1750,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
