#!/usr/bin/env python3
"""Run the Mesen test scripts in tests/ against a ROM.

    python3 tests/run.py                  # every test, against out/gimmick-1.5.nes
    python3 tests/run.py recall coyote    # just these
    python3 tests/run.py --rom "Gimmick! (Japan).nes" ramguard   # against the original
    python3 tests/run.py perf             # a survey from tests/survey/

Each test is tests/t_<name>.lua; surveys (measurements that do not pass or
fail) are tests/survey/s_<name>.lua. The script is joined to tests/lib.lua and
run with `Mesen --testRunner`. Logs and screenshots go to out/test/.
"""
import glob
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "test")
MESEN = os.path.join(REPO, "Mesen")


def run(name, rom):
    src = os.path.join(REPO, "tests", "t_%s.lua" % name)
    if not os.path.exists(src):
        src = os.path.join(REPO, "tests", "survey", "s_%s.lua" % name)
    script = os.path.join(OUT, "%s.lua" % name)
    with open(script, "w") as f:
        f.write('REPO = %r\nNAME = %r\nHACK = %s\n' % (REPO, name, "false" if "Japan" in rom else "true"))
        f.write(open(os.path.join(REPO, "tests", "lib.lua")).read())
        f.write("\n-- ---- %s\n" % os.path.basename(src))
        f.write(open(src).read())
    log = os.path.join(OUT, "%s.log" % name)
    if os.path.exists(log):
        os.remove(log)
    try:
        subprocess.run([MESEN, "--testRunner", rom, script], cwd=REPO, timeout=600,
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
    args = sys.argv[1:]
    rom = os.path.join(REPO, "out", "gimmick-1.5.nes")
    if args[:1] == ["--rom"]:
        rom = os.path.abspath(args[1])
        args = args[2:]
    os.makedirs(OUT, exist_ok=True)
    names = args or sorted(os.path.basename(p)[2:-4] for p in glob.glob(os.path.join(REPO, "tests", "t_*.lua")))
    bad = 0
    for n in names:
        ok, msg = run(n, rom)
        bad += not ok
        print("%-4s %-16s %s" % ("ok" if ok else "FAIL", n, "" if ok else msg))
    print("%d/%d passed" % (len(names) - bad, len(names)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
