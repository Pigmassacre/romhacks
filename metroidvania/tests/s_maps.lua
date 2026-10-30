-- Not a test: the collision map of every stage and floor, as text, for
-- planning routes. Samus flies along each floor; each cell on screen is read
-- from Castlevania's map ($05A0). Writes out/test/maps.txt.
-- Stair table as in s_allstairs: y, floor, type, x.
STAIRS = {
  [1] = {{192,0,0,624}, {128,0,2,680}, {128,0,0,720}, {96,0,2,744}, {96,0,3,912}, {128,0,1,944}, {192,0,0,1296}, {96,0,2,1384}},
  [2] = {{80,0,1,96}, {112,0,1,448}, {128,1,3,176}, {192,1,1,240}, {192,1,3,48}, {192,1,3,368}, {192,1,1,464}, {128,1,3,400}},
  [3] = {{96,0,3,112}, {128,0,1,144}, {128,0,3,304}, {192,0,1,368}, {160,0,0,688}, {128,0,2,712}},
  [4] = {{192,0,0,368}, {128,0,2,424}, {96,0,0,336}, {128,1,2,456}},
  [5] = {{64,0,0,48}, {176,1,2,88}},
  [6] = {{144,0,0,160}, {112,0,2,184}, {64,0,0,656}, {160,1,2,712}},
  [7] = {{112,0,1,160}, {176,1,3,64}, {176,1,0,64}, {112,1,2,120}, {176,1,0,384}, {144,1,2,408}, {112,1,3,576}, {176,1,1,640}},
  [8] = {{144,0,0,576}, {80,0,2,632}, {80,0,1,640}, {144,1,3,544}},
  [13] = {{80,0,1,128}, {80,0,3,416}, {176,0,0,384}, {112,0,2,440}, {112,0,1,448}, {176,1,3,64}, {80,1,3,128}, {144,1,1,192}, {80,1,3,352}, {144,1,1,416}},
  [14] = {{176,0,0,1152}, {112,0,2,1208}, {112,0,1,1152}, {80,0,3,1120}, {80,0,0,1056}, {176,1,2,1112}, {176,1,0,1152}, {80,1,2,1240}, {80,1,3,864}, {144,1,1,928}, {176,1,1,768}, {112,1,3,704}, {144,1,1,416}, {80,1,3,352}, {80,1,3,64}, {176,1,1,160}},
  [15] = {{176,0,1,672}, {80,0,3,576}, {80,0,0,896}, {176,1,2,952}},
  [16] = {{176,0,1,1440}, {112,0,3,1376}},
  [17] = {{144,0,0,544}, {80,0,2,608}, {80,0,0,640}, {80,0,0,288}, {176,0,1,224}, {48,0,3,96}, {80,0,3,128}, {80,0,0,64}, {176,1,2,696}, {176,1,0,640}, {112,1,2,696}, {112,1,1,704}, {80,1,3,672}, {144,1,3,320}, {176,1,1,352}, {176,1,2,344}, {176,1,2,120}, {176,1,1,128}, {112,1,3,64}},
  [18] = {{112,0,1,672}, {144,1,3,544}},
}
local SCREEN0 = {[0]=0,0,0,0,0,1,0,0,1,0,0,0,0,1,0,0,1,0,1,0}
local OUTF = io.open(OUT .. "maps.txt", "w")
local function cell(x, y)
  local X = (x % 256) // 8
  local idx = (X >> 2) + ((y & 0xF8) - 0x30)
  local sc = SCREEN0[r(0x28)] + (x >> 8)
  local a = 0x5A0 + idx + ((sc & 1) == 1 and 0xB0 or 0)
  return (r(a) >> (2 * ((X ~ 3) & 3))) & 3
end
local function x() return r(0x122) + 256 * r(0x123) end
local stage, last = tonumber(os.getenv("MAP_FROM") or "1"), tonumber(os.getenv("MAP_TO") or "18")
local phase, t0, died, dir, seen, floors, tries, ent, stillc, lx, y0 = "towarp", 0, false, nil, {}, {}, 0, nil, 0, 0, 0
local start = {}
local function record()
  local F = r(0x46)
  seen[F] = seen[F] or {}
  local s = r(0x2E) + 256 * r(0x2F)
  for px = s + 8, s + 247, 8 do
    local cx = px // 8
    seen[F][cx] = seen[F][cx] or {}
    for y = 0x30, 0xD8, 8 do seen[F][cx][y] = cell(px, y) end
  end
end
local function flush()
  for F, cols in pairs(seen) do
    local minx, maxx = 1e9, 0
    for cx in pairs(cols) do minx = math.min(minx, cx); maxx = math.max(maxx, cx) end
    OUTF:write(string.format("=== stage %d floor %d  x %04x-%04x  start %s\n", stage, F, minx * 8, maxx * 8 + 7, start[F] or "?"))
    local marks = {}
    for i, e in ipairs(STAIRS[stage] or {}) do if e[2] == F then marks[e[4] // 8 .. "," .. e[1]] = i % 10 end end
    local h = "     "
    for cx = minx, maxx do h = h .. ((cx % 32 == 0) and string.format("%-32s", string.format("|%03x", cx * 8)) or "") end
    OUTF:write(h .. "\n")
    for y = 0x30, 0xD8, 8 do
      local l = string.format("%02x   ", y)
      for cx = minx, maxx do
        local v = cols[cx] and cols[cx][y] or 0
        local m = marks[cx .. "," .. y]
        l = l .. (m and tostring(m) or (v == 0 and "." or (v == 1 and "#" or (v == 2 and "%" or "@"))))
      end
      OUTF:write(l .. "\n")
    end
  end
  OUTF:flush()
end
local function nextstage()
  flush()
  stage = stage + 1; seen = {}; start = {}; floors = {}; tries = 0; died = false; phase = "towarp"
  if stage > last then OUTF:close(); log("PASS"); done() end
end
local function untried()
  local F = r(0x46)
  local list = STAIRS[stage] or {}
  while true do
    tries = tries + 1
    local e = list[tries]
    if not e then return nil end
    if e[2] == F then return e end
  end
end
loadstate_raw("castle", function() end)
INPUT = function(f)
  if phase == "flyL" or phase == "flyR" or phase == "tostair" then return dir end
  if phase == "press" and f > t0 + 2 then return ent[3] >= 2 and pad("D") or pad("U") end
  return {}
end
FRAME = function(f)
  if phase ~= "warp" and phase ~= "towarp" then w(0x118, 9); w(0x5B, 0x40); w(0x43, 3) end
  if phase == "towarp" and r(0x18) == 8 then w(0x28, stage); w(0x29, stage); w(0x2A, 9) end
  if phase == "towarp" and r(0x18) == 5 then
    w(0x28, stage); w(0x29, stage); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9); phase = "warp"
  end
  if r(0x18) == 6 then died = true end
  if phase == "warp" and not died and r(0x18) == 5 then w(0x5B, 0); w(0x113, 0); w(0x45, 0) end
  if f > 400000 then log("FAIL timeout"); done() end
  if phase == "warp" and died and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == stage and (r(0x126) & 1) == 1 then
    start[r(0x46)] = string.format("x %04x y %02x", x(), r(0x124))
    phase = "flyL"; t0 = f; y0 = r(0x124) - 0x18; stillc = 0
  end
  if phase == "flyL" or phase == "flyR" then
    dir = phase == "flyL" and pad("L") or pad("R")
    w(0x1C0, 0x80); w(0x124, y0); w(0x10B, 0); w(0x109, 0)
    record()
    if x() == lx then stillc = stillc + 1 else stillc = 0 end
    lx = x()
    if stillc > 30 or r(0x18) ~= 5 or f > t0 + 4000 then
      if phase == "flyL" then phase = "flyR"; t0 = f; stillc = 0
      else
        floors[r(0x46)] = true
        ent = untried()
        if not ent then w(0x1C0, 0); nextstage() else phase = "tostair"; t0 = f end
      end
    end
  end
  if phase == "tostair" then
    local tx = ent[4] + ({0, -1, 5, 2})[ent[3] + 1]
    w(0x1C0, 0x80); w(0x124, ent[1] + 1 - 0x10); w(0x10B, 0); w(0x109, 0)
    local d = tx - x()
    if math.abs(d) <= 2 then
      w(0x122, tx % 256); w(0x123, tx // 256); w(0x124, ent[1] + 1 - 4); w(0x1C0, 0); phase = "land"; t0 = f
    else dir = d > 0 and pad("R") or pad("L") end
    if f > t0 + 3000 then ent = untried(); if not ent then w(0x1C0, 0); nextstage() else t0 = f end end
  end
  if phase == "land" and f == t0 + 40 then phase = "press"; t0 = f end
  if phase == "press" and f > t0 + 20 and r(0x46C) ~= 4 and r(0x46C) ~= 6 then
    if r(0x18) ~= 5 or r(0x28) ~= stage then nextstage()
    elseif not floors[r(0x46)] then
      start[r(0x46)] = string.format("x %04x y %02x", x(), r(0x124))
      tries = 0; phase = "flyL"; t0 = f; y0 = r(0x124) - 0x18; stillc = 0
    else
      ent = untried()
      if not ent then nextstage() else phase = "tostair"; t0 = f end
    end
  end
end
