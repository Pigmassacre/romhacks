#!/usr/bin/env python3
"""Record a reference run of the NES game in Mesen, into out/trace/.

    python3 tools/record.py [frames] [trace-from trace-to]
    python3 tools/record.py --idle [frames]

The trace logs every instruction between two NMIs into steps.txt, for
tools/stepdiff.py. --idle presses nothing, into out/trace_idle/, so the translator
also sees what the title screen leads to.
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
idle = "--idle" in sys.argv
if idle:
    sys.argv.remove("--idle")
OUT = os.path.join(REPO, "out", "trace_idle" if idle else "trace") + "/"
os.makedirs(OUT, exist_ok=True)
frames = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
script = os.path.join(OUT, "record.lua")
with open(script, "w") as f:
    f.write("OUT = %r\nFRAMES = %d\n" % (OUT, frames))
    if idle:
        f.write("IDLE = true\n")
    if len(sys.argv) > 3:
        f.write("TRACE_FROM = %s\nTRACE_TO = %s\n" % (sys.argv[2], sys.argv[3]))
    f.write(open(os.path.join(REPO, "tests", "s_record.lua")).read())
subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=500",
                os.path.join(REPO, "Gimmick! (Japan).nes"), script], cwd=REPO, timeout=540)
