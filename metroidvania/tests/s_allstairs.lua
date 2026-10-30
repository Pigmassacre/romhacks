-- Not a test: every staircase in the game. For each stair end, Samus flies
-- there, lands, presses Up (at a foot) or Down (at a top) and holds it; the
-- log says where she ended up.

-- Castlevania's stair table ($FBEC, bank 6), by stage: y, floor, type (bit 1:
-- a top, Down climbs; else a foot, Up climbs), x in the stage.
STAIRS = {
  [0] = {},
  [1] = {{192,0,0,624}, {128,0,2,680}, {128,0,0,720}, {96,0,2,744}, {96,0,3,912}, {128,0,1,944}, {192,0,0,1296}, {96,0,2,1384}},
  [2] = {{80,0,1,96}, {112,0,1,448}, {128,1,3,176}, {192,1,1,240}, {192,1,3,48}, {192,1,3,368}, {192,1,1,464}, {128,1,3,400}},
  [3] = {{96,0,3,112}, {128,0,1,144}, {128,0,3,304}, {192,0,1,368}, {160,0,0,688}, {128,0,2,712}},
  [4] = {{192,0,0,368}, {128,0,2,424}, {96,0,0,336}, {128,1,2,456}},
  [5] = {{64,0,0,48}, {176,1,2,88}},
  [6] = {{144,0,0,160}, {112,0,2,184}, {64,0,0,656}, {160,1,2,712}},
  [7] = {{112,0,1,160}, {176,1,3,64}, {176,1,0,64}, {112,1,2,120}, {176,1,0,384}, {144,1,2,408}, {112,1,3,576}, {176,1,1,640}},
  [8] = {{144,0,0,576}, {80,0,2,632}, {80,0,1,640}, {144,1,3,544}},
  [9] = {},
  [10] = {},
  [11] = {},
  [12] = {},
  [13] = {{80,0,1,128}, {80,0,3,416}, {176,0,0,384}, {112,0,2,440}, {112,0,1,448}, {176,1,3,64}, {80,1,3,128}, {144,1,1,192}, {80,1,3,352}, {144,1,1,416}},
  [14] = {{176,0,0,1152}, {112,0,2,1208}, {112,0,1,1152}, {80,0,3,1120}, {80,0,0,1056}, {176,1,2,1112}, {176,1,0,1152}, {80,1,2,1240}, {80,1,3,864}, {144,1,1,928}, {176,1,1,768}, {112,1,3,704}, {144,1,1,416}, {80,1,3,352}, {80,1,3,64}, {176,1,1,160}},
  [15] = {{176,0,1,672}, {80,0,3,576}, {80,0,0,896}, {176,1,2,952}},
  [16] = {{176,0,1,1440}, {112,0,3,1376}},
  [17] = {{144,0,0,544}, {80,0,2,608}, {80,0,0,640}, {80,0,0,288}, {176,0,1,224}, {48,0,3,96}, {80,0,3,128}, {80,0,0,64}, {176,1,2,696}, {176,1,0,640}, {112,1,2,696}, {112,1,1,704}, {80,1,3,672}, {144,1,3,320}, {176,1,1,352}, {176,1,2,344}, {176,1,2,120}, {176,1,1,128}, {112,1,3,64}},
  [18] = {{112,0,1,672}, {144,1,3,544}},
}
local stage = tonumber(os.getenv("ST_FROM") or "1")
local last = tonumber(os.getenv("ST_TO") or "18")
local idx, phase, t0, e, dir, maxact = 0, "next", 0, nil, nil, 0
local function x() return r(0x122) + 256 * r(0x123) end
local died = false
local function warp()
  phase = "towarp"; died = false
end
local function nextentry()
  idx = idx + 1
  while not STAIRS[stage] or idx > #STAIRS[stage] do
    stage = stage + 1; idx = 1
    if stage > last then return false end
  end
  e = STAIRS[stage][idx]
  return true
end
loadstate_raw("castle", function() phase = "next" end)
INPUT = function(f)
  if phase == "fly" then return dir end
  if phase == "press" and f > t0 + 2 then return e[3] >= 2 and pad("D") or pad("U") end
  return {}
end
local function st() return string.format("act %d st %02x x %04x y %02x scr %02x%02x mode %02x/%02x stage %d floor %d accy %02x", r(0x46C), r(0x100), x(), r(0x124), r(0x2F), r(0x2E), r(0x18), r(0x19), r(0x28), r(0x46), r(0x10B)) end
FRAME = function(f)
  if phase ~= "warp" and phase ~= "towarp" then w(0x118, 9); w(0x5B, 0x40) end
  if phase == "next" then
    if not nextentry() then log("PASS"); done() return end
    warp()
  end
  if phase == "towarp" and r(0x18) == 5 then
    w(0x28, stage); w(0x29, stage); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
    phase = "warp"
  end
  if phase == "towarp" and r(0x18) == 8 then w(0x28, stage); w(0x29, stage); w(0x2A, 9) end
  if r(0x18) == 6 then died = true end
  if f > 200000 then log("FAIL timeout " .. phase); done() end
  if phase == "warp" and died and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == stage and (r(0x126) & 1) == 1 then
    if r(0x46) ~= e[2] then
      log(string.format("stage %d #%d (y %02x f%d t%d x %04x): skipped, on floor %d", stage, idx, e[1], e[2], e[3], e[4], r(0x46)))
      phase = "next"
    else
      phase = "fly"; t0 = f
    end
  end
  if phase == "fly" then
    local tx = e[4] + ({0, -1, 5, 2})[e[3] + 1]
    w(0x1C0, 0x80); w(0x124, e[1] + 1 - 0x10); w(0x10B, 0); w(0x109, 0)
    local d = tx - x()
    if math.abs(d) <= 2 then
      w(0x122, tx % 256); w(0x123, tx // 256); w(0x124, e[1] + 1 - 4)
      w(0x1C0, 0); phase = "land"; t0 = f
    else
      dir = d > 0 and pad("R") or pad("L")
    end
    if f > t0 + 3000 then log(string.format("stage %d #%d: couldn't fly there (%s)", stage, idx, st())); phase = "next" end
  end
  if phase == "land" and f == t0 + 40 then
    phase = "press"; t0 = f; maxact = 0
    log(string.format("stage %d #%d (y %02x f%d t%d x %04x): landed %s", stage, idx, e[1], e[2], e[3], e[4], st()))
  end
  if phase == "press" then
    local a = r(0x46C)
    if a == 4 or a == 6 then maxact = 4 end
    if f == t0 + 20 and maxact == 0 then
      log("   no stairs: " .. st()); shot(string.format("%02d_%d_nostairs", stage, idx)); phase = "next"
    end
    if maxact == 4 and a ~= 4 and a ~= 6 or r(0x18) ~= 5 or r(0x28) ~= stage then phase = "after"; t0 = f; log("   off at " .. st()) end
    if f > t0 + 1500 then log("   still on: " .. st()); phase = "next" end
  end
  if phase == "after" and f == t0 + 60 then
    log("   then " .. st()); shot(string.format("%02d_%d", stage, idx)); phase = "next"
  end
end
