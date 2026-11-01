#!/usr/bin/env python3
"""Play the NES game in Mesen and record what the SNES build has to know.

    python3 tools/survey.py          # out/survey/, a tour of the whole game
    python3 tools/survey.py --chr    # out/survey_chr/, how it uses CHR pages
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHR = "--chr" in sys.argv
SCRIPT = "s_snd.lua" if "--snd" in sys.argv else "s_oam.lua" if "--oam" in sys.argv else "s_creads.lua" if "--creads" in sys.argv else "s_chr.lua" if CHR else "s_survey.lua"
OUT = os.path.join(REPO, "out", "survey_snd" if "--snd" in sys.argv else "survey_oam" if "--oam" in sys.argv else "survey_c" if "--creads" in sys.argv else "survey_chr" if CHR else "survey") + "/"
os.makedirs(OUT, exist_ok=True)
script = OUT + "survey.lua"
with open(script, "w") as f:
    f.write("OUT = %r\nSHOTS = %s\n" % (OUT, "true" if CHR else "false"))
    f.write(open(os.path.join(REPO, "tests", SCRIPT)).read())
    f.write(open(os.path.join(REPO, "tests", "s_tour.lua")).read())
subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=3400",
                os.path.join(REPO, "Gimmick! (Japan).nes"), script], cwd=REPO, timeout=3450,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
