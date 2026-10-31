#!/usr/bin/env python3
"""Run the Mesen test scripts in tests/ against the hack.

    python3 tests/run.py                  # make the savestates, then every test
    python3 tests/run.py star             # just these (the savestates must exist)

Each test is tests/t_<name>.lua, each sweep tests/s_<name>.lua. tests/s_states.lua
makes the savestates the tests start from; it runs first when no test is named.
The script is joined to tests/lib.lua and run with `Mesen --testRunner`. Logs,
screenshots and savestates go to out/test/.
"""
import glob
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "test")
MESEN = os.path.join(REPO, "Mesen")
ROM = os.path.join(REPO, "out", "smb3-gimmick.nes")


def run(name, rom, timeout):
    src = os.path.join(REPO, "tests", "t_%s.lua" % name)
    if not os.path.exists(src):
        src = os.path.join(REPO, "tests", "s_%s.lua" % name)
    tag = os.environ.get("RUN_TAG", "")
    script = os.path.join(OUT, "%s%s.lua" % (name, tag))
    with open(script, "w") as f:
        f.write("REPO = %r\nOUT = %r\nNAME = %r\nFNS = %r\n" % (REPO, OUT + "/", name + tag, os.path.join(REPO, "out", "smb3.fns")))
        f.write(open(os.path.join(REPO, "tests", "lib.lua")).read())
        f.write("\n-- ---- %s\n" % os.path.basename(src))
        f.write(open(src).read())
    log = os.path.join(OUT, "%s%s.log" % (name, tag))
    if os.path.exists(log):
        os.remove(log)
    try:
        subprocess.run([MESEN, "--testRunner", "--timeout=%d" % timeout, rom, script], cwd=REPO, timeout=timeout + 50,
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
    timeout = int(os.environ.get("RUN_TIMEOUT", "850"))
    if not names:
        ok, msg = run("states", ROM, timeout)
        if not ok:
            print("FAIL making the savestates: " + msg)
            sys.exit(1)
        names = sorted(os.path.basename(p)[2:-4] for p in glob.glob(os.path.join(REPO, "tests", "t_*.lua")))
    bad = 0
    for n in names:
        ok, msg = run(n, ROM, timeout)
        bad += not ok
        print("%-4s %-16s %s" % ("ok" if ok else "FAIL", n, "" if ok else msg), flush=True)
    print("%d/%d passed" % (len(names) - bad, len(names)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
