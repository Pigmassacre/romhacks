#!/usr/bin/env python3
"""Play the NES game in Mesen and record what the SNES build has to know: what code runs
and which banks it needs, how it uses the sound hardware, and the world map.

    python3 tools/survey.py    # out/survey/
"""
import os
import subprocess

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "survey") + "/"


def run(name, tour):
    os.makedirs(OUT, exist_ok=True)
    script = OUT + name + ".lua"
    with open(script, "w") as f:
        f.write("OUT = %r\nSHOTS = false\n" % OUT)
        f.write(open(os.path.join(REPO, "tests", name + ".lua")).read())
        if tour:
            f.write(open(os.path.join(REPO, "tests", "s_tour.lua")).read())
    subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=3400",
                    os.path.join(REPO, "Gimmick! (Japan).nes"), script], cwd=REPO, timeout=3450,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


run("s_survey", True)
run("s_snd", True)
run("s_map", False)
