#!/usr/bin/env python3
"""Run the replay build in mGBA (Flatpak) and print what it measured.

    python3 tools/run_gba.py [seconds]

mGBA's window opens on your screen while it runs. The ROM prints to mGBA's log,
which only reaches a file reliably, so that is what this reads. The full recording
takes about 200 seconds, because the RAM check slows it down.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "gba_log") + "/"
ROM = os.path.join(REPO, "out", "gimmick_replay.gba")
FRAME_CYCLES = 280896

seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 215
os.makedirs(OUT, exist_ok=True)
log = OUT + "mgba.log"
open(log, "w").close()
try:
    subprocess.run(["flatpak", "run", "--filesystem=" + REPO, "io.mgba.mGBA", "-C", "logToFile=1",
                    "-C", "logFile=" + log, "-C", "logLevel=8", "-C", "fpsTarget=240", ROM],
                   timeout=seconds, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except subprocess.TimeoutExpired:
    pass
# Ending the launcher leaves mGBA running inside its sandbox.
subprocess.run(["flatpak", "kill", "io.mgba.mGBA"], stderr=subprocess.DEVNULL)
values = re.findall(r"GBA Debug: (\w+)=(\d+)", open(log, errors="replace").read())
windows, final, current = [], None, {}
for key, value in values:
    value = int(value)
    if key == "nmi":
        current = {"nmi": value}
        windows.append(current)
    elif key == "done" and value and final is None:
        final = dict(current)
    else:
        current[key] = value
for w in windows:
    if final and w["nmi"] > final.get("nmi", 0):
        break
    print("to frame %6d: average %3.0f%% (draw %2.0f%%, sound %2.0f%%), worst %3.0f%%, over budget on %3d, drew %3d of 500, longest gap %3d, first bad RAM: %s" % (
        w["nmi"], 100 * w["avg_500"] / FRAME_CYCLES, 100 * w["draw_500"] / FRAME_CYCLES, 100 * w["mix_500"] / FRAME_CYCLES,
        100 * w["max_500"] / FRAME_CYCLES, w["over_500"], w["drawn_500"], w["gap_500"], w["first_bad"] or "none"))
if final:
    print("whole run: %.0f%% on average, over budget on %d of %d frames; RAM checked at %d NMIs, first bad: %s" % (
        100 * final["cycles_sum"] / (final["frames"] - 1) / FRAME_CYCLES, final["over_budget"], final["frames"],
        final["checked"], final["first_bad"] or "none"))
else:
    print("the recording did not finish in %d seconds" % seconds)
