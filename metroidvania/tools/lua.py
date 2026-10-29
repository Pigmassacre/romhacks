#!/usr/bin/env python3
"""Run a Lua script in Mesen's test runner: tools/lua.py script.lua [rom]

The script gets OUT (out/lua/) and REPO defined first, and tools/lib.lua.
"""
import os, subprocess, sys
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "lua")
os.makedirs(OUT, exist_ok=True)
src = os.path.abspath(sys.argv[1])
rom = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.join(REPO, "Castlevania I.nes")
name = os.path.splitext(os.path.basename(src))[0]
script = os.path.join(OUT, name + "_run.lua")
with open(script, "w") as f:
    f.write("REPO=%r\nOUT=%r\nNAME=%r\n" % (REPO, OUT + "/", name))
    f.write(open(os.path.join(REPO, "tools", "lib.lua")).read() + "\n")
    f.write("REPO = %r\n" % REPO)
    f.write(open(src).read())
try:
    subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", rom, script], cwd=REPO, timeout=int(os.environ.get("T", "300")))
except subprocess.TimeoutExpired:
    print("timeout")
log = os.path.join(OUT, name + ".log")
if os.path.exists(log):
    print(open(log).read())
