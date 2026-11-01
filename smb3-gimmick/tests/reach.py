#!/usr/bin/env python3
"""What Yumetaro can reach of each area, from out/test/map_<name>.txt (tests/s_maps.lua).

Simulates his jump (speed, gravity, body) from every place he can stand, on the tiles alone:
plain jumps, then jumps from a star on the ground (16 px up), then from a star thrown out over a
gap. Prints where each stops, for the areas where the plain jump doesn't reach the end, with the
moving platforms and other objects past that point. Pipes, doors and enemies to ride aren't known
to it, so a stop is a place to look at, not a verdict.
"""
import glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLATFORMS = {0x24, 0x26, 0x27, 0x28, 0x2C, 0x2E, 0x36, 0x37, 0x38, 0x3A, 0x3C, 0x3E, 0x44, 0x47, 0x49, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xAE}


def load(path):
    lines = open(path).read().splitlines()
    h = re.match(r"(\S+) width (\d+) vert (\d+) start (-?\d+),(-?\d+)", lines[0])
    rows, objs = [], []
    for l in lines[1:]:
        if l.startswith("obj"):
            a = l.split()
            objs.append((int(a[1], 16), int(a[2]), int(a[3])))
        else:
            rows.append(l[3:])
    return h.group(1), int(h.group(3)), int(h.group(4)), int(h.group(5)), rows, objs


class Map:
    def __init__(self, rows):
        self.r, self.h, self.w = rows, len(rows), len(rows[0])

    def at(self, c, r):
        if c < 0 or c >= self.w:
            return "#"
        if r < 0 or r >= self.h:
            return "."
        ch = self.r[r][c]
        return {"P": "#", "D": "."}.get(ch, ch)

    def raw(self, c, r):
        return self.r[r][c] if 0 <= c < self.w and 0 <= r < self.h else "."

    def solid(self, x, y):
        return self.at(x // 16, y // 16) == "#"

    def top(self, x, y):
        return self.at(x // 16, y // 16) in "#="


def fly(m, x, y, dirn, delay, vy=-84.0, step=1.44):
    """A full jump from foot position (x, y): where he lands. x is his centre, y his feet."""
    yv = vy
    fy = float(y)
    fx = float(x)
    t = 0
    while t < 400:
        t += 1
        yv = min(yv + 4, 127)
        ny = fy + yv / 16
        if t > delay:
            nx = fx + dirn * step
            if not m.solid(int(nx) + dirn * 5, int(fy) - 8) and not m.solid(int(nx) + dirn * 5, int(fy) - 1):
                fx = nx
        if yv < 0:
            if m.solid(int(fx), int(ny) - 16):
                yv = 0
                ny = fy
        else:
            for px in (int(fx) - 4, int(fx) + 4):
                # only by coming down onto the top of a tile with room above it
                if m.top(px, int(ny)) and int(ny) // 16 > int(fy) // 16 and m.at(px // 16, int(ny) // 16 - 1) != "#":
                    return (px // 16, int(ny) // 16)
        fy = ny
        if fy > m.h * 16:
            return None
    return None


def stand(m):
    s = set()
    for r in range(1, m.h):
        for c in range(m.w):
            if m.at(c, r) in "#=" and m.at(c, r - 1) in ".~":
                s.add((c, r))
    return s


def walk(m, c, r, d):
    n = c + d
    if m.at(n, r - 1) == "#":
        return None
    if m.at(n, r) in "#=":
        return (n, r)
    for q in range(r, m.h):
        if m.at(n, q) == "#" or (m.at(n, q) == "=" and q > r):
            return (n, q)
    return None


def reach(m, start, tier):
    seen = set()
    todo = [start]
    while todo:
        c, r = todo.pop()
        if (c, r) in seen or not (0 <= c < m.w and 0 <= r < m.h):
            continue
        seen.add((c, r))
        for d in (-1, 1):
            n = walk(m, c, r, d)
            if n:
                todo.append(n)
        x, y = c * 16 + 8, r * 16
        ups = [0]
        if tier >= 2:
            ups.append(16)
        for up in ups:
            for d in (-1, 1):
                for off in (-6, 0, 6):
                    for delay in (0, 10, 20, 30):
                        n = fly(m, x + off, y - up, d, delay)
                        if n:
                            todo.append(n)
                if tier >= 3:
                    # a star thrown out over a gap, ridden for a while
                    for k in (16, 32, 48, 64):
                        if m.solid(x + d * k, y - 8):
                            break
                        n = fly(m, x + d * k, y - 16 + k // 8, d, 0)
                        if n:
                            todo.append(n)
    return seen


def main():
    names = sys.argv[1:] or sorted(os.path.basename(p)[4:-4] for p in glob.glob(os.path.join(ROOT, "out", "test", "map_*.txt")))
    for name in names:
        n, vert, sx, sy, rows, objs = load(os.path.join(ROOT, "out", "test", "map_%s.txt" % name))
        if vert or any("~" in r for r in rows):
            continue
        m = Map(rows)
        ss = stand(m)
        c0 = sx // 16
        r0 = None
        for q in range((sy + 24) // 16, m.h):
            if (c0, q) in ss:
                r0 = q
                break
        if r0 is None:
            print(name, "no floor under the start")
            continue
        end = max((o[1] for o in objs if o[0] == 0x41), default=max(c for c, r in ss))
        res = []
        for t in (1, 2, 3):
            got = reach(m, (c0, r0), t)
            res.append(max(c for c, r in got))
            ways = sorted(set(c for c, r in got for dc in (-1, 0, 1) for dr in (-5, -4, -3, -2, -1, 0) if m.raw(c + dc, r + dr) in "PD" and (m.raw(c + dc, r + dr) == "D" or dr in (0, -3, -4, -5))))
            if res[-1] >= end - 1:
                break
        if res[0] >= end - 1:
            continue
        stop = res[-1]
        past = sorted(set("%02x@%d" % (o[0], o[1]) for o in objs if o[0] in PLATFORMS and stop - 12 <= o[1] <= stop + 30))
        print("%-18s end %3d reach %s %s%s" % (name, end, "/".join(map(str, res)), "ways at %s " % ways[:6] if ways else "", "platforms " + " ".join(past[:6]) if past else ""))


main()
