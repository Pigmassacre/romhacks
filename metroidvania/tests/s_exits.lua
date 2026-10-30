-- Not a test: every stage's exit. Samus is taken to the exit's floor (up
-- the stairs that lead there), flown to that end of the stage, dropped at
-- the exit's height and walked into the edge.

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
-- Castlevania's exit table ($FC12): floor, y, screen x. The boss stages
-- (3, 6, 9, 12, 15, 18) end with the orb instead; their entries go unused.
EXITS = { [1] = {0, 0x60, 0xF0}, [2] = {1, 0x60, 0xF0}, [4] = {1, 0x60, 0x17}, [5] = {1, 0x80, 0x17},
  [7] = {1, 0x90, 0xE8}, [8] = {1, 0x70, 0xE8}, [10] = {0, 0x40, 0xD0}, [11] = {0, 0xB0, 0xF2},
  [13] = {1, 0xB0, 0xE8}, [14] = {1, 0xB0, 0x1C}, [17] = {1, 0x70, 0x10} }
-- the stairs (in STAIRS) that take Samus to the exit's floor. (Stage 14's
-- don't lead to its exit: they come out where a wall is between Samus and
-- it, and Simon too stops at that wall.)
UP = { [4] = 3, [5] = 1, [7] = 1, [8] = 3, [13] = 1, [14] = 5, [17] = 3 }
local stage = tonumber(os.getenv("EX_FROM") or "1")
local last = tonumber(os.getenv("EX_TO") or "17")
local phase, t0, dir, e, died, ent = "towarp", 0, nil, nil, false, nil
local function x() return r(0x122) + 256 * r(0x123) end
local function st() return string.format("act %d st %02x x %04x sx %02x y %02x scr %02x%02x mode %02x/%02x stage %d floor %d", r(0x46C), r(0x100), x(), r(0x38C), r(0x124), r(0x2F), r(0x2E), r(0x18), r(0x19), r(0x28), r(0x46)) end
while not EXITS[stage] do stage = stage + 1 end
loadstate_raw("castle", function() end)
INPUT = function(f)
  if phase == "fly" or phase == "walk" or phase == "stairfly" then return dir end
  if phase == "press" and f > t0 + 2 then return ent[3] >= 2 and pad("D") or pad("U") end
  return {}
end
local function nextstage()
  repeat stage = stage + 1 until EXITS[stage] or stage > last
  if stage > last then log("PASS"); done() return end
  phase = "towarp"; died = false
end
FRAME = function(f)
  if phase ~= "warp" and phase ~= "towarp" then w(0x118, 9); w(0x5B, 0x40) end
  if phase == "towarp" and r(0x18) == 5 then
    w(0x28, stage); w(0x29, stage); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9); phase = "warp"
  end
  if r(0x18) == 6 then died = true end
  if phase == "warp" and not died and r(0x18) == 5 then w(0x5B, 0); w(0x113, 0); w(0x45, 0) end
  if f > 200000 then log("FAIL timeout"); done() end
  if phase == "warp" and died and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == stage and (r(0x126) & 1) == 1 then
    e = EXITS[stage]
    if r(0x46) ~= e[1] and UP[stage] then ent = STAIRS[stage][UP[stage]]; phase = "stairfly"; t0 = f
    elseif r(0x46) ~= e[1] then log(string.format("stage %d: on floor %d, exit on %d", stage, r(0x46), e[1])); nextstage()
    else phase = "fly"; t0 = f end
  end
  if phase == "stairfly" then
    local tx = ent[4] + ({0, -1, 5, 2})[ent[3] + 1]
    w(0x1C0, 0x80); w(0x124, ent[1] + 1 - 0x10); w(0x10B, 0); w(0x109, 0)
    local d = tx - x()
    if math.abs(d) <= 2 then
      w(0x122, tx % 256); w(0x123, tx // 256); w(0x124, ent[1] + 1 - 4); w(0x1C0, 0); phase = "land"; t0 = f
    else dir = d > 0 and pad("R") or pad("L") end
  end
  if phase == "land" and f == t0 + 40 then phase = "press"; t0 = f end
  if phase == "press" and f > t0 + 20 and r(0x46C) ~= 4 and r(0x46C) ~= 6 then
    if r(0x46) == e[1] then phase = "fly"; t0 = f else log(string.format("stage %d: stairs didn't take her to floor %d: %s", stage, e[1], st())); nextstage() end
  end
  if phase == "fly" then
    dir = e[3] >= 0x80 and pad("R") or pad("L")
    w(0x1C0, 0x80); w(0x124, e[2] + 1 - 0x18); w(0x10B, 0); w(0x109, 0)
    local sx = r(0x38C)
    local edge = e[3] >= 0x80 and math.min(0xE0, e[3] - 0x10) or math.max(0x20, e[3] + 0x10)
    if (e[3] >= 0x80 and sx >= edge) or (e[3] < 0x80 and sx <= edge) then
      w(0x124, e[2] + 1 - 4); w(0x1C0, 0); phase = "walk"; t0 = f
    end
    if f > t0 + 4000 then log(string.format("stage %d: couldn't fly to the end: %s", stage, st())); nextstage() end
  end
  if phase == "walk" then
    if r(0x18) ~= 5 or r(0x28) ~= stage then
      log(string.format("stage %d exit (f%d y %02x x %02x): ok, %s", stage, e[1], e[2], e[3], st())); shot(string.format("%02d", stage)); nextstage()
    elseif f > t0 + 200 then
      log(string.format("stage %d exit (f%d y %02x x %02x): NOT REACHED, %s", stage, e[1], e[2], e[3], st())); shot(string.format("%02d_no", stage)); nextstage()
    end
  end
end
