#!/usr/bin/env python3
"""Run Gimmick! 1.5's own tests on the SNES build, with its options off (expecting the
original game) and on (expecting 1.5).

    python3 tools/test15.py [test names]    # logs in ../gimmick-1.5/out/test/
"""
import glob
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(REPO), "gimmick-1.5")
OUT = os.path.join(ROOT, "out", "test")
ROM = os.path.join(REPO, "out", "gimmick.sfc")
SKIP = {"title", "ramguard"}    # 1.5's logo is not in this port; the RAM guard reads ROM by NES address


def opt_flags():
    for line in open(os.path.join(REPO, "out", "gen", "labels.txt")):
        m = re.match(r"al ([0-9A-F]+) \.opt_flags$", line)
        if m:
            return int(m.group(1), 16)
    sys.exit("build first")


# After the library, in place of what it says about the machine.
SHIM = """
local add = emu.addMemoryCallback
emu.addMemoryCallback = function(fn, kind, a, b)
  -- Code runs in banks $A0-$BF here, so a watch on an address is one in each of them.
  if kind == emu.callbackType.exec and b < 0x10000 then
    for k = 0xA0, 0xBF do add(fn, kind, k * 65536 + a, k * 65536 + b) end
  else
    return add(fn, kind, a, b)
  end
end
M = emu.memType.snesMemory
local D = emu.memType.snesDebug
function r(a) if a < 0x2000 then return emu.read(a, M) end return emu.read(0xA00000 + a, M) end
function w(a, v)
  if a < 0x2000 then emu.write(a, v % 256, emu.memType.snesWorkRam)
  elseif a >= 0x6000 and a < 0x8000 then emu.write(a - 0x6000, v % 256, emu.memType.snesSaveRam)
  else emu.write(0xA00000 + a, v % 256, D) end
end
emu.addEventCallback(function() emu.write(OPT_AT, OPT_VAL, emu.memType.snesWorkRam) end, emu.eventType.startFrame)
"""
SNES_PAD = """
local function snes_pad(i)
  local o = {}
  for k, v in pairs(i) do o[k] = v end
  o.b, o.y = i.a, i.b
  o.a = nil
  return o
end
"""


def run(name, on):
    src = os.path.join(ROOT, "tests", "t_%s.lua" % name)
    lib = open(os.path.join(ROOT, "tests", "lib.lua")).read()
    lib = lib.replace("emu.setInput(inp, 0)", "emu.setInput(snes_pad(inp), 0)")
    lib = lib.replace("emu.callbackType.exec, 0x8000, 0xFFFF", "emu.callbackType.exec, 0xA08000, 0xBFFFFF")
    lib = lib.replace('function r(a) return emu.read(a, M) end', 'function r(a) return 0 end')
    lib = lib.replace('M = emu.memType.nesMemory', 'M = emu.memType.snesMemory')
    # The library reads RAM while it loads and while it runs, so r and w go first of all.
    script = os.path.join(OUT, "snes_%s.lua" % name)
    with open(script, "w") as f:
        f.write("REPO = %r\nNAME = %r\nHACK = %s\n" % (ROOT, name, "true" if on else "false"))
        f.write(SNES_PAD)
        f.write(lib)
        f.write(SHIM.replace("OPT_AT", str(opt_flags())).replace("OPT_VAL", "31" if on else "0"))
        f.write(open(src).read())
    log = os.path.join(OUT, name + ".log")
    if os.path.exists(log):
        os.remove(log)
    try:
        subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", ROM, script], cwd=REPO, timeout=300,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    if not os.path.exists(log):
        return False, "no log"
    lines = open(log).read().splitlines()
    fails = [l for l in lines if l.startswith("FAIL")]
    ok = bool(lines) and lines[-1] == "PASS"
    return ok, ("%d checks" % sum(l.startswith("ok") for l in lines)) if ok else "; ".join(fails[:3]) or (lines[-1] if lines else "empty")


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:] or [n for n in sorted(os.path.basename(p)[2:-4] for p in glob.glob(os.path.join(ROOT, "tests", "t_*.lua"))) if n not in SKIP]
    bad = 0
    for on in (False, True):
        print("options", "on (expect Gimmick! 1.5)" if on else "off (expect the original game)")
        for n in names:
            ok, msg = run(n, on)
            bad += not ok
            print("  %-8s %s  %s" % (n, "ok  " if ok else "FAIL", msg[:150]))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
