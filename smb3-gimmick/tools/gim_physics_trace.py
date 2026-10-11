#!/usr/bin/env python3
"""Record frame-by-frame traces of Yumetaro and the star from the real game.

Each scenario boots Gimmick! (J) in Mesen, plays a scripted input sequence on
stage 1 and writes out/gimtrace/<name>.trc. The Godot reference implementation
replays these and must match on every frame:

    python3 tools/gim_physics_trace.py            # record every scenario
    python3 tools/gim_physics_trace.py star ride  # or just some of them
    godot --headless --path godot -s tests/verify_traces.gd -- out/gimtrace

A trace is a list of chunks. "M" + 8192 bytes is a dump of $6000-$7FFF (the
map and the tile attribute tables). "F" + flags + one byte per address in
ADDRS is the state at the end of a frame. Flag bit 0 means the script poked
memory on that frame, so the verifier takes the state as given.

Scenarios poke memory to get at things stage 1 does not offer near the start:
they move Yumetaro, turn the ground into ice, or change what a slope does.
Enemies are removed every frame unless a scenario keeps them.
"""
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out", "gimtrace") + "/"
ROM = os.path.join(REPO, "Gimmick! (Japan).nes")
MESEN = os.path.join(REPO, "Mesen")
T0 = 700  # frames from power-on to stage 1 being playable

ADDRS = [
    0x14, 0x15, 0x16, 0x35, 0x3E, 0x4B, 0x53, 0x55, 0xED, 0xF5, 0xF7,
    0x90, 0x91, 0x9A, 0x9B, 0xA4, 0xA5, 0xAE, 0xAF, 0xB8, 0xB9, 0xC2, 0xC3, 0xCC, 0xCD, 0xD6, 0xD7,
    0x300, 0x301, 0x30A, 0x30B, 0x314, 0x315, 0x31E, 0x31F, 0x328, 0x329, 0x332, 0x333, 0x33C, 0x33D,
    0x346, 0x351, 0x35A, 0x35B, 0x364, 0x365, 0x36E, 0x36F, 0x378, 0x379,
    0x382, 0x383, 0x38C, 0x38D, 0x397, 0x3A1, 0x3C8, 0x3C9, 0x2B, 0x36, 0x37, 0x38, 0x39,
]
BUTTONS = {"A": "a", "B": "b", "L": "left", "R": "right", "U": "up", "D": "down"}

FLOOR_TYPE = 0x7D00  # + metatile id
VARIANT = 0x7F00
GROUND = 0x0A        # the metatile under the start of stage 1
SLOPE_TILES = (0x20, 0x31, 0x32, 0x23, 0x21)

LUA = r'''
local OUT = "%(out)s"
local M = emu.memType.nesMemory
local function r(a) return emu.read(a, M) end
-- nesDebug writes reach the cartridge RAM even while the mapper has it write-protected.
local function w(a, v) emu.write(a, v, emu.memType.nesDebug) end
local T0 = %(t0)d
local f = 0
local addrs = {%(addrs)s}
local inputs = {%(inputs)s}
local pokes = {}
%(pokes)s
local ride = {%(ride)s}
local h = io.open(OUT .. "%(name)s.trc", "wb")

local function dumpmap()
  local t = {"M"}
  for a = 0x6000, 0x7FFF do t[#t + 1] = string.char(r(a)) end
  h:write(table.concat(t))
end

emu.addEventCallback(function()
  local inp = {}
  if f < 560 and r(0x90) == 0 then inp.start = (f %% 60) < 5 end
  local k = f - T0
  for _, s in ipairs(inputs) do
    if k >= s[1] and k < s[2] then for b in pairs(s[3]) do inp[b] = true end end
  end
  emu.setInput(inp, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  f = f + 1
  local k = f - T0
  if k < 0 then return end
  local flags = (k == 0) and 1 or 0
  local mapdirty = (k == 0)
  if not %(keep)s then
    for s = 2, 9 do w(0x90 + s, 0) w(0xD6 + s, 0) end
  end
  if pokes[k] then
    flags = 1
    for _, p in ipairs(pokes[k]) do
      w(p[1], p[2])
      if p[1] >= 0x6000 then mapdirty = true end
    end
  end
  if ride[k] then
    -- Put Yumetaro exactly on top of the star.
    flags = 1
    local top = r(0xA5) * 256 + r(0x9B) - 0xF0
    w(0xB8, r(0xB9)) w(0xAE, r(0xAF)) w(0x9A, top %% 256) w(0xA4, top // 256) w(0xC2, 0) w(0xCC, 0)
  end
  if mapdirty then dumpmap() end
  local t = {"F", string.char(flags)}
  for _, a in ipairs(addrs) do t[#t + 1] = string.char(r(a)) end
  h:write(table.concat(t))
  if k == %(length)d then h:close() emu.stop(0) end
end, emu.eventType.endFrame)
'''


def at(column, row, screen=1, xsub=0x80, ysub=0):
    """Pokes that put Yumetaro at a tile, standing still."""
    return [(0xB8, column), (0xAE, xsub), (0xA4, screen * 16 + row), (0x9A, ysub), (0xC2, 0), (0xCC, 0), (0x4B, 0)]


def record(name, inputs, length, pokes=(), ride=(), keep_enemies=False):
    poke_lines = []
    for frame, plist in pokes:
        poke_lines.append("pokes[%d] = pokes[%d] or {}" % (frame, frame))
        for addr, value in plist:
            poke_lines.append("table.insert(pokes[%d], {%d, %d})" % (frame, addr, value))
    lua = LUA % dict(
        out=OUT, t0=T0, name=name, length=length,
        addrs=",".join(str(a) for a in ADDRS),
        inputs=",".join("{%d,%d,{%s}}" % (s, e, ",".join("%s=true" % BUTTONS[c] for c in b)) for s, e, b in inputs),
        pokes="\n".join(poke_lines),
        ride=",".join("[%d]=true" % k for k in ride),
        keep="true" if keep_enemies else "false",
    )
    script = OUT + name + ".lua"
    with open(script, "w") as fh:
        fh.write(lua)
    subprocess.run(["timeout", "300", MESEN, "--testRunner", ROM, script], cwd=REPO,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("%-10s %d bytes" % (name, os.path.getsize(OUT + name + ".trc")))


S = {}
# Walking, turning and every kind of jump on the flat ground at the start.
S["basic"] = dict(length=1200, inputs=[
    (10, 70, "R"), (110, 140, "L"), (180, 182, "A"), (240, 280, "A"), (320, 380, "RA"), (420, 470, "L"),
    (470, 480, "LA"), (520, 526, "A"), (560, 600, "R"), (600, 640, "L"), (640, 700, "R"), (700, 701, "A"),
    (701, 760, "R"), (800, 900, "L"), (900, 904, "A"), (960, 975, "RA"), (1000, 1012, "A"), (1050, 1051, "A"),
    (1052, 1053, "A"), (1100, 1108, "LA")])
# Cancelled charges, the shortest throw, throws while standing, walking, rising and falling.
S["star"] = dict(length=2500, inputs=[
    (10, 30, "B"), (60, 110, "B"), (300, 301, "L"), (310, 360, "B"), (560, 570, "R"), (570, 640, "RB"),
    (640, 660, "R"), (860, 900, "B"), (895, 930, "A"), (1100, 1140, "B"), (1120, 1125, "A"), (1140, 1160, "L"),
    (1400, 1433, "B"), (1500, 1534, "B"), (1700, 1790, "B"), (1900, 1940, "LB"), (1940, 2000, "L"),
    (2200, 2250, "B"), (2230, 2260, "R")])
S["walls"] = dict(length=1600, inputs=[
    (10, 120, "L"), (120, 125, "LA"), (125, 200, "L"), (220, 420, "R"), (420, 440, "RA"), (440, 640, "R"),
    (500, 502, "A"), (560, 590, "A"), (700, 760, "L"), (800, 840, "B"), (1000, 1050, "LB"), (1050, 1100, "L"),
    (1300, 1350, "RB")])
S["slopes"] = dict(length=2000, pokes=[(2, at(28, 10))], inputs=[
    (10, 200, "R"), (260, 420, "L"), (480, 560, "R"), (560, 564, "A"), (620, 680, "RA"), (700, 760, "B"),
    (900, 940, "LB"), (1100, 1105, "A"), (1160, 1260, "R"), (1200, 1240, "B"), (1300, 1500, "L"),
    (1340, 1344, "A"), (1400, 1440, "A"), (1600, 1700, "R"), (1640, 1680, "B")])
S["slopeidle"] = dict(length=1300, inputs=[(400, 440, "B"), (700, 740, "B"), (1000, 1040, "B")], pokes=[
    (2, at(30, 9, ysub=0x80)), (100, at(31, 9)), (200, at(34, 9)), (300, at(35, 9, ysub=0x80)),
    (400, at(32, 9)), (700, at(31, 9)), (1000, at(35, 9))])
S["conveyor"] = dict(length=900, pokes=[(2, at(26, 10))], inputs=[
    (60, 120, "R"), (160, 260, "L"), (300, 304, "A"), (360, 400, "B"), (600, 640, "LB"), (700, 800, "R")])
S["ride"] = dict(length=1500, ride=[66, 356, 656, 956, 1268],
    pokes=[(2, at(6, 10)), (290, at(6, 10)), (590, at(6, 10)), (890, at(6, 10)), (1190, at(4, 10))],
    inputs=[(10, 60, "B"), (300, 350, "B"), (380, 400, "R"), (600, 650, "B"), (672, 676, "A"), (900, 950, "B"),
            (965, 1000, "L"), (1200, 1250, "RB"), (1250, 1262, "R")])
S["ridewall"] = dict(length=1000, ride=[64, 354, 652, 766],
    pokes=[(2, at(5, 10)), (288, at(9, 10)), (590, at(11, 10)), (690, at(3, 10))],
    inputs=[(5, 6, "L"), (10, 60, "B"), (300, 350, "B"), (290, 291, "R"), (600, 650, "B"), (700, 750, "LB"),
            (750, 760, "L")])
# Enemies stay: the first one hurts Yumetaro, the second kills him.
S["hurt"] = dict(length=1000, keep_enemies=True, inputs=[(10, 900, "R"), (200, 203, "A"), (420, 460, "B")])
S["hurt2"] = dict(length=1300, keep_enemies=True, inputs=[
    (10, 400, "R"), (400, 700, "L"), (450, 500, "B"), (700, 1200, "R"), (760, 790, "A"), (900, 960, "B")])
S["ice"] = dict(length=1300, pokes=[(2, at(6, 10) + [(FLOOR_TYPE + GROUND, 7)])], inputs=[
    (10, 90, "R"), (220, 290, "L"), (290, 330, "R"), (400, 404, "A"), (440, 500, "RA"), (600, 650, "B"),
    (800, 860, "LB"), (1000, 1002, "R"), (1100, 1102, "L")])
for name, floor_type in (("push5", 5), ("push6", 6)):
    S[name] = dict(length=600,
        pokes=[(2, at(8, 10) + [(FLOOR_TYPE + GROUND, floor_type)]), (200, at(8, 10)), (400, at(10, 10))],
        inputs=[(100, 160, "L"), (200, 204, "A"), (260, 300, "B"), (420, 520, "L"), (520, 560, "R")])
# All twenty slope behaviours, one after another on the same two hills.
_inputs, _pokes = [], []
for b in range(20):
    o = b * 300
    _pokes.append((o + 2, at(28, 10) + [(VARIANT + t, b) for t in SLOPE_TILES]))
    _inputs += [(o + 10, o + 100, "R"), (o + 160, o + 220, "L"), (o + 230, o + 234, "A"), (o + 250, o + 290, "B")]
S["slopebeh"] = dict(length=6000, inputs=_inputs, pokes=_pokes)
# The tube at the end of the first room, which also changes the vertical screen.
S["tube"] = dict(length=500, pokes=[(2, at(58, 10))], inputs=[(10, 200, "R")])
S["startube"] = dict(length=500, pokes=[(2, at(57, 10) + [(0x30A, 1)])], inputs=[(10, 60, "B"), (200, 250, "B"), (240, 246, "A")])
S["ceiling"] = dict(length=700,
    pokes=[(2, at(19, 8)), (290, at(19, 8, xsub=0xF0)), (390, at(18, 8, xsub=0x10)), (490, at(18, 8, xsub=0xC0))],
    inputs=[(10, 40, "A"), (100, 103, "A"), (160, 220, "B"), (205, 240, "A"), (300, 340, "LA"), (400, 460, "RA"),
            (500, 560, "B"), (545, 548, "A")])
# The ground turns lethal under his feet: the pit death, then the spike death.
S["lethal0"] = dict(length=400, inputs=[(10, 60, "R")], pokes=[(40, [(FLOOR_TYPE + GROUND, 0)])])
S["lethal1"] = dict(length=400, inputs=[(10, 60, "R"), (20, 80, "B")],
    pokes=[(60, [(FLOOR_TYPE + GROUND, 0), (VARIANT + GROUND, 1)])])
# Yumetaro is moved far away from a bouncing star, so the camera leaves it behind.
S["despawn"] = dict(length=500, inputs=[(10, 60, "B"), (200, 250, "B"), (250, 251, "L")],
    pokes=[(70, at(30, 5)), (260, at(40, 5))])
S["edge"] = dict(length=900, pokes=[(2, at(19, 8)), (290, at(20, 8)), (690, at(13, 9))], inputs=[
    (10, 200, "R"), (300, 420, "L"), (500, 560, "B"), (700, 800, "R"), (740, 744, "A")])


if __name__ == "__main__":
    for path in (ROM, MESEN):
        if not os.path.exists(path):
            sys.exit("missing " + path)
    os.makedirs(OUT, exist_ok=True)
    with open(OUT + "addrs.json", "w") as fh:
        json.dump(ADDRS, fh)
    for name in sys.argv[1:] or list(S):
        record(name, **S[name])
