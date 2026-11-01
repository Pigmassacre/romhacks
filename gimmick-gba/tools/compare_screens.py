#!/usr/bin/env python3
"""Draw every marked moment of the tour as the GBA would show it, beside Mesen's own
screenshot of that frame, on contact sheets in out/screens/.

    python3 tools/compare_screens.py
"""
import glob
import os
import subprocess

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRACE = os.path.join(REPO, "out", "trace_tour")
OUT = os.path.join(REPO, "out", "screens")
PER_SHEET = 24

os.makedirs(OUT, exist_ok=True)
marks = [l.split() for l in open(os.path.join(TRACE, "tour.txt")) if len(l.split()) == 2]
with open(os.path.join(OUT, "list.txt"), "w") as f:
    for frame, name in marks:
        f.write("%s %s\n" % (frame, name))
frames = sum(1 for _ in open(os.path.join(TRACE, "cpu.txt")))
env = dict(os.environ, SHOTS=os.path.join(OUT, "list.txt"), SHOT_DIR=OUT)
subprocess.run([os.path.join(REPO, "out", "host"), os.path.join(REPO, "Gimmick! (Japan).nes"), TRACE, str(frames), "/dev/null"],
               env=env, check=True, stderr=subprocess.DEVNULL)
pairs = []
for frame, name in marks:
    mine, theirs = os.path.join(OUT, name + ".ppm"), os.path.join(TRACE, "shot_" + name + ".png")
    if os.path.exists(mine) and os.path.exists(theirs):
        pairs.append((mine, theirs))
for sheet in range(0, len(pairs), PER_SHEET):
    chunk = pairs[sheet:sheet + PER_SHEET]
    args, parts = [], []
    for i, (a, b) in enumerate(chunk):
        args += ["-i", a, "-i", b]
        parts.append("[%d]scale=180:120:flags=neighbor[a%d];[%d]scale=150:120[b%d];[a%d][b%d]hstack[p%d]" % (i * 2, i, i * 2 + 1, i, i, i, i))
    n = len(chunk)
    layout = "|".join("%d_%d" % ((i % 4) * 340, (i // 4 % 6) * 124) for i in range(n))
    stack = "".join("[p%d]" % i for i in range(n)) + ("xstack=inputs=%d:layout=%s:fill=gray" % (n, layout) if n > 1 else "null")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y"] + args + ["-filter_complex", ";".join(parts) + ";" + stack,
                    os.path.join(OUT, "sheet_%02d.png" % (sheet // PER_SHEET))], check=True)
print("%d screens on %d sheets" % (len(pairs), (len(pairs) + PER_SHEET - 1) // PER_SHEET))
