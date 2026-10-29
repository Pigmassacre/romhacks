#!/usr/bin/env python3
"""Run the Mesen test scripts in tests/ against the hack.

    python3 tests/run.py                  # make the savestates, then every test
    python3 tests/run.py physics          # just these (the savestates must exist)
    python3 tests/run.py --rom "Castlevania I.nes" ramguard   # against the original

Each test is tests/t_<name>.lua. tests/s_states.lua makes the savestates the
tests start from; it runs first when no test is named. The script is joined
to tests/lib.lua and run with `Mesen --testRunner`. Logs, screenshots and
savestates go to out/test/.
"""
import glob
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "test")
MESEN = os.path.join(REPO, "Mesen")
ROM = os.path.join(REPO, "out", "metroidvania.nes")


def run(name, rom):
    src = os.path.join(REPO, "tests", "t_%s.lua" % name)
    if not os.path.exists(src):
        src = os.path.join(REPO, "tests", "s_%s.lua" % name)
    script = os.path.join(OUT, "%s.lua" % name)
    with open(script, "w") as f:
        f.write("REPO = %r\nOUT = %r\nNAME = %r\nHACK = %s\n" % (REPO, OUT + "/", name, "false" if "Castlevania" in rom else "true"))
        f.write(open(os.path.join(REPO, "tests", "lib.lua")).read())
        f.write("\n-- ---- %s\n" % os.path.basename(src))
        f.write(open(src).read())
    log = os.path.join(OUT, "%s.log" % name)
    if os.path.exists(log):
        os.remove(log)
    try:
        subprocess.run([MESEN, "--testRunner", rom, script], cwd=REPO, timeout=900,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    if not os.path.exists(log):
        return False, "no log"
    lines = open(log).read().splitlines()
    ok = bool(lines) and lines[-1] == "PASS"
    fails = [l for l in lines if l.startswith("FAIL")]
    return ok, "; ".join(fails[:3]) if fails else (lines[-1] if lines else "")


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:]
    rom = ROM
    if names[:1] == ["--rom"]:
        rom = os.path.abspath(names[1])
        names = names[2:]
    if not names:
        ok, msg = run("states", rom)
        if not ok:
            print("FAIL making the savestates: " + msg)
            sys.exit(1)
        names = sorted(os.path.basename(p)[2:-4] for p in glob.glob(os.path.join(REPO, "tests", "t_*.lua")))
    bad = 0
    for n in names:
        ok, msg = run(n, rom)
        bad += not ok
        print("%-4s %-16s %s" % ("ok" if ok else "FAIL", n, "" if ok else msg))
    print("%d/%d passed" % (len(names) - bad, len(names)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
