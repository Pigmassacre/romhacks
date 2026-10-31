-- Not a test of one thing: the whole game, played from the title to the ending
-- with controller inputs alone. No warps, no flying: a bot walks each stage's
-- route (ROUTES below), jumps walls and pits, climbs stairs, shoots what is in
-- its way and fights the bosses.
--
--   PLAY_FROM=n  start at stage n, from the savestate an earlier run left
--                (out/test/play_<n>.mss)
--   PLAY_WARP=1  with PLAY_FROM: warp there from the castle savestate instead
--   PLAY_DELAY=n with PLAY_WARP: wait n frames first (the moving platforms'
--                timing decides whether its jumps land)
--   PLAY_TO=n    stop after stage n
--   PLAY_HONEST=1  no help at all: hits hurt, and dying costs a life
--   PLAY_HITS=1    hits land and knock her back, but energy and lives are topped up
-- Otherwise she can't be hurt, which is enough to show the way is open. The
-- log has a line per stage and a screenshot per stretch (play_<stage>_<n>.png).

-- Castlevania's stair table ($FBEC, bank 6), by stage: y, floor, type (bit 1:
-- a top, Down climbs; else a foot, Up climbs), x in the stage.
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
-- Each stage's route: {"go", x}, {"stair", index into STAIRS}, {"exit", "R"/"L"}
-- (walk that way until the stage ends), {"boss", "R"/"L"} (walk that way until
-- the screen locks, fight, take the orb).
ROUTES = dofile(REPO .. "/tests/play_routes.lua")

local HONEST = os.getenv("PLAY_HONEST") ~= nil
local first = tonumber(os.getenv("PLAY_FROM") or "1")
local last = tonumber(os.getenv("PLAY_TO") or "18")

local SCREEN0 = {[0]=0,0,0,0,0,1,0,0,1,0,0,0,0,1,0,0,1,0,1,0}
local function cell(px, y)
  if y < 0x30 or y >= 0xE0 then return 0 end
  local X = (px % 256) // 8
  local idx = (X >> 2) + ((y & 0xF8) - 0x30)
  local sc = SCREEN0[r(0x28)] + (px >> 8)
  return (r(0x5A0 + idx + ((sc & 1) == 1 and 0xB0 or 0)) >> (2 * ((X ~ 3) & 3))) & 3
end
local function x() return r(0x122) + 256 * r(0x123) end
local function playing() return r(0x18) == 5 and r(0x19) == 6 end
local function st() return string.format("act %d st %02x x %04x sx %02x y %02x scr %02x%02x mode %02x/%02x stage %d floor %d lock %d bosshp %02x en %x%02x lives %d time %x%02x", r(0x46C), r(0x100), x(), r(0x38C), r(0x124), r(0x2F), r(0x2E), r(0x18), r(0x19), r(0x28), r(0x46), r(0x48), r(0x1A9), r(0x118), r(0x117), r(0x2A), r(0x43), r(0x42)) end

local stage, stepi, step, phase = nil, 1, nil, "title"
local tStep, quest2 = 0, false
local tStage, lastx, still, jump, jwait, shots, deaths, hitsTaken, n = 0, 0, 0, 0, 0, 0, 0, 0, 0
local lastEn, lastMode, onStair, fightT, hop = 0, -1, false, 0, 0
local function route() return ROUTES[stage] or {} end
local function nextstep()
  tStep = F
  stepi = stepi + 1
  step = route()[stepi]
  phase = "step"; onStair = false; still = 0
end
local function beginStage()
  stage = r(0x28)
  stepi = 0
  nextstep()
  tStage = F; hop = 0; fightT = 0
  log(string.format("--- stage %d starts: %s", stage, st()))
end

-- The moving platforms (AI 1, pose $C9, slots $17-$1A): {level x, y}.
local function platforms()
  local t, scroll = {}, r(0x2E) + 256 * r(0x2F)
  for slot = 0x17, 0x1A do
    if r(0x434 + slot) == 1 and r(0x31C + slot) == 0xC9 then t[#t + 1] = {scroll + r(0x38C + slot), r(0x354 + slot), slot} end
  end
  return t
end
-- How far it is, from x px, to the next ground going d, near the height of
-- the feet (above them by a jump, or below them).
local function gap(px, feet, d)
  for w = 8, 200, 8 do
    for y = feet - 0x18, math.min(feet + 0x18, 0xD8), 8 do
      if cell(px + d * w, y) ~= 0 and cell(px + d * w, y - 8) == 0 and cell(px + d * w, y - 16) == 0 then return w end
    end
  end
  return 999
end
-- A platform worth jumping for: on its way towards her, or close by. Jumped for
-- on its way off, it's gone by the time she comes down.
local platX = {}
local function coming(p, px)
  local away = platX[p[3]] and (p[1] - platX[p[3]]) * (p[1] - px) > 0
  return not away or math.abs(p[1] - px) <= 32
end
local REACH = 56         -- a running jump, with room to spare
local aim                -- the platform she jumped for
local dropTo             -- where she is stepping down to

-- Walking towards d (1 right, -1 left), jumping what is in the way.
local function walk(d, t)
  t = t or {}
  local px, y = x(), r(0x124)
  local feet = y + 0x10
  local grounded = r(0x10B) == 0
  local go = d
  local riding
  for _, p in ipairs(platforms()) do
    if p[2] == y + r(0x101) and math.abs(p[1] - px) <= 21 then riding = p end
  end
  if grounded and jump == 0 and jwait == 0 then aim = nil end
  if grounded then dropTo = nil end
  if jump > 0 then
    jump = jump - 1
    t.a = true
  elseif jwait > 0 then
    jwait = jwait - 1
  elseif riding and grounded and d ~= 0 then
    -- on a platform: stay on it until the next ground comes within reach
    go = 0
    if (px - riding[1]) * d < 0 and F % 8 < 4 then go = d end     -- edge along it
    local head = cell(px - d * 8, y - 0x18) == 0 and cell(px, y - 0x18) == 0 and cell(px + d * 8, y - 0x18) == 0 and cell(px + d * 16, y - 0x18) == 0
    if head and gap(px, feet, d) <= 46 then jump = 24; jwait = 8; go = d end
    for _, p in ipairs(platforms()) do
      -- or the next platform
      if p[3] ~= riding[3] and (p[1] - px) * d > 24 and (p[1] - px) * d < 72 and coming(p, px) then jump = 24; jwait = 8; go = d; aim = p[3] end
    end
  elseif grounded and d ~= 0 then
    local wall = cell(px + d * 12, y) ~= 0 or cell(px + d * 12, y - 8) ~= 0 or cell(px + d * 12, y + 8) ~= 0
    -- (as late as she can: from 8 pixels back, a 32 pixel gap is a near thing)
    local pit = cell(px + d * 5, feet) == 0 and cell(px + d * 5, feet + 8) == 0
    local widegap = not pit and (stage == 4 or stage == 5 or stage == 10)
      and cell(px + d * 40, feet) == 0 and cell(px + d * 40, feet + 8) == 0 and gap(px + d * 32, feet, d) > REACH
    if wall or (still > 20 and not pit and not widegap) then jump = (still > 60) and 12 or 24; jwait = 8
    elseif widegap then
      -- a wide gap coming: slow down, to stop at its edge
      if F % 4 >= 2 and still < 2 then go = 0 end
    elseif pit then
      local w = gap(px, feet, d)
      if os.getenv("PLAY_TRACE") then log(string.format("      pit at %04x y %02x f%d: gap %d, %d platforms", px, y, r(0x46), w, #platforms())) end
      local below = false
      for yy = feet, 0xD8, 8 do if cell(px + d * 16, yy) ~= 0 then below = true end end
      if w <= REACH then jump = 24; jwait = 8
      elseif below and stage ~= 5 then
        -- ground further down: step off, and come down on it (stage 5's only
        -- leads away from its exit: the platforms are the way)
        dropTo = px + d * 16
      elseif not (stage == 4 or stage == 5 or stage == 10) then jump = 24; jwait = 8
      else
        -- too wide: wait for a platform to come within reach
        go = 0
        for _, p in ipairs(platforms()) do
          local near = (p[1] - px) * d
          if near > 24 and near < 56 + 16 and p[2] > feet - 0x28 and coming(p, px) then jump = 24; jwait = 8; go = d; aim = p[3] end
        end
        if (#platforms() == 0 or stage == 4) and still > 60 and stage ~= 10 then jump = 24; jwait = 8; go = d end   -- none coming: try it
      end
    end
  end
  if F % 4 == 0 then for _, p in ipairs(platforms()) do platX[p[3]] = p[1] end end
  if dropTo and not grounded then
    go = 0
    if math.abs(dropTo - px) > 2 then go = dropTo > px and 1 or -1 end
  end
  if aim and not grounded then
    -- in the air: steer for it
    local dx = r(0x2E) + 256 * r(0x2F) + r(0x38C + aim) - px
    go = 0
    if math.abs(dx) > 4 then go = dx > 0 and 1 or -1 end
  end
  -- stage 6's crushers kill: wait for them to lift, as anyone must
  if stage == 6 and r(0x46) == 0 and go ~= 0 and grounded then
    for i = 0, 2 do
      local cx = r(0x150 + i) + 256 * r(0x153 + i) + 0x0A
      local ahead = (cx - px) * go
      if ahead > 8 and ahead < 44 and (r(0x156 + i) & 0x0F) > 1 then go = 0 end
    end
  end
  if go > 0 then t.right = true elseif go < 0 then t.left = true end
  return t
end

local stairx = function(e) return e[4] + ({0, -1, 5, 2})[e[3] + 1] end

INPUT = function(f)
  if phase == "title" then return {start = f % 120 < 3 and f > 60} end
  if phase == "continue" then return {start = f % 40 == 0} end
  if not playing() or phase ~= "step" or not step then return {} end
  local t = {}
  if f % 14 == 0 then t.b = true end
  local kind = step[1]
  if kind == "go" then
    return walk(step[2] > x() and 1 or -1, t)
  elseif kind == "up" then
    local d = step[2] > x() and 1 or -1
    if math.abs(step[2] - x()) <= 6 then d = 0 end
    t = walk(d, t)
    if r(0x10B) == 0 and f % 30 < 2 then jump = 20 end
    return t
  elseif kind == "leap" then
    -- a running jump: from x step[2], holding on until x step[3]
    local dir = step[3] > x() and 1 or -1
    t = {b = t.b}
    if dir > 0 then t.right = true else t.left = true end
    if (x() - step[2]) * dir >= 0 and hop == 0 then hop = 1 end
    if hop > 0 then hop = hop + 1 end
    if hop > 1 and hop < 44 then t.a = true end
    if hop > 1 and (x() - step[3]) * dir >= 0 then t.left = nil; t.right = nil end
    return t
  elseif kind == "hop" then
    -- straight up, then over: onto something above, from beside it
    t = {b = t.b}
    if r(0x10B) == 0 and hop == 0 then hop = 1 end
    if hop > 0 then hop = hop + 1 end
    if hop > 4 and hop < 44 then t.a = true end
    if hop > 8 then
      local far = step[3] and (step[2] == "R" and x() >= step[3] or step[2] == "L" and x() <= step[3])
      if not far then if step[2] == "R" then t.right = true else t.left = true end end
    end
    return t
  elseif kind == "stair" then
    local e = STAIRS[stage][step[2]]
    local a = r(0x46C)
    if a == 4 or a == 6 then return e[3] >= 2 and {down = true, b = t.b} or {up = true, b = t.b} end
    local d = stairx(e) - x()
    if r(0x124) ~= e[1] + 1 and r(0x10B) == 0 then return walk(d > 0 and 1 or -1, t) end
    if r(0x10B) ~= 0 and r(0x124) < e[1] then
      -- dropping to a stair's top: land on the floor beside it
      if e[3] == 3 and d > -8 then return {left = true} end
      if e[3] == 2 and d < 8 then return {right = true} end
    end
    if math.abs(d) <= 2 and r(0x10B) == 0 then
      -- stand still, then a fresh press
      if r(0x108) == 0 and f % 16 < 8 then return e[3] >= 2 and {down = true} or {up = true} end
      return {}
    end
    if math.abs(d) <= 2 then return {} end
    if math.abs(d) < 12 and r(0x10B) ~= 0 then return d > 0 and {right = true} or {left = true} end
    if math.abs(d) < 12 then
      -- tap, to stop on it
      if f % 8 >= 3 then return {} end
      return d > 0 and {right = true} or {left = true}
    end
    return walk(d > 0 and 1 or -1, t)
  elseif kind == "exit" then
    return walk(step[2] == "R" and 1 or -1, t)
  elseif kind == "boss" then
    if r(0x48) == 0 and r(0x1A9) ~= 0 then
      return walk(step[2] == "R" and 1 or -1, t)
    end
    -- the fight: shoot, up every so often, jump, pace
    local tt = {}
    if f % 8 == 0 then tt.b = true end
    if (f // 90) % 3 == 1 then tt.up = true end
    if f % 70 < 25 and (f // 70) % 2 == 0 then tt.a = true end
    local sx = r(0x38C)
    local goright = (f // 150) % 2 == 0
    if sx < 0x30 then goright = true elseif sx > 0xD0 then goright = false end
    if f % 12 < 4 or r(0x1A9) == 0 then if goright then tt.right = true else tt.left = true end end
    return tt
  end
  return t
end

-- The last frames, for looking back on when she dies.
local RING, ringi = {}, 0
local function trace()
  ringi = ringi + 1
  local pl = ""
  for slot = 0x17, 0x1A do
    if r(0x434 + slot) == 1 and r(0x31C + slot) == 0xC9 then pl = pl .. string.format(" p%04x,%02x", r(0x2E) + 256 * r(0x2F) + r(0x38C + slot), r(0x354 + slot)) end
  end
  RING[ringi % 300] = string.format("%d x %04x y %02x sx %02x scr %02x%02x st %02x acc %02x spdx %02x spdy %02x act %d hit %02x rad %02x en %x%02x fc %02x pause %02x %02x", F, x(), r(0x124), r(0x38C), r(0x2F), r(0x2E), r(0x100), r(0x10B), r(0x108), r(0x109), r(0x46C), r(0x107), r(0x101), r(0x118), r(0x117), r(0x1A), r(0x22), r(0x4A)) .. pl .. string.format(" ride %02x", r(0x12A))
end
local function dumptrace(every)
  for i = ringi - 299, ringi, every or 3 do if RING[i % 300] then log("      " .. RING[i % 300]) end end
end

local function fail(msg)
  dumptrace()
  local c = emu.getState()
  local b, u = {}, {}
  for i = 0, 15 do b[#b + 1] = string.format("%02x", r(0x100 + c["cpu.sp"] + 1 + i)) end
  for i = 0, 33 do u[#u + 1] = string.format("%02x", r(0x7CF + i)) end
  log(string.format("  cpu: pc %04x sp %02x a %02x x %02x y %02x, $1B %02x, bank %02x, depth %02x, buffer %02x from %02x, stack %s", c["cpu.pc"], c["cpu.sp"], c["cpu.a"], c["cpu.x"], c["cpu.y"], r(0x1B), r(0x27), r(0x1BE), r(0x20), r(0x128), table.concat(b, " ")))
  log("  shots: " .. table.concat(u, " "))
  log("STUCK " .. msg .. ": " .. st())
  shot(string.format("stuck_%02d", stage or 0))
  FAILS = FAILS + 1
  done()
end

local warped, warpwait = false, tonumber(os.getenv("PLAY_DELAY") or "0")
if os.getenv("PLAY_WARP") then
  loadstate_raw("castle", function()
    w(0x28, first); w(0x29, first); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
    phase = "warp"
  end)
elseif first > 1 then
  loadstate_raw(string.format("play_%d", first), function() phase = "wait" end)
end

FRAME = function(f)
  local mode = r(0x18)
  if phase == "warp" then
    if mode == 6 then warped = true end
    if warped and playing() and r(0x28) == first and (r(0x126) & 1) == 1 then
      if warpwait == 0 then phase = "wait" end
      warpwait = warpwait - 1
    end
    return
  end
  local cheat = not HONEST
  if os.getenv("PLAY_HITS") then
    cheat = false
    if stage then w(0x118, 9); w(0x2A, 9) end
  end
  if cheat and stage then w(0x5B, 0x40); w(0x118, 9) end
  if f > 900000 then fail("out of frames") end

  if phase == "title" and mode == 5 then phase = "wait" end
  trace()

  -- the mode changes, for the log
  local m = mode * 256 + r(0x19)
  if m ~= lastMode and mode ~= 5 then log(string.format("    f %d mode %02x/%02x stage %d", f, mode, r(0x19), r(0x28))) end
  lastMode = m

  if mode == 0x0D then
    if phase ~= "continue" then log("GAME OVER: " .. st()); shot("gameover"); deaths = deaths + 1; phase = "continue" end
    return
  end
  if phase == "continue" and playing() then phase = "wait" end

  if mode == 6 and phase ~= "dead" and phase ~= "wait" then
    deaths = deaths + 1
    log(string.format("    died (%d): %s", deaths, st()))
    dumptrace()
    shot(string.format("died_%02d", deaths))
    if deaths >= tonumber(os.getenv("PLAY_DEATHS") or "4") then
      log("too many deaths"); FAILS = FAILS + 1; done(); return
    end
    phase = "wait"; stage = nil
  end

  if mode == 0x0F and phase ~= "ending" then
    log(string.format("THE ENDING at frame %d, %d deaths", f, deaths)); shot("ending"); phase = "ending"; tStage = f; n = 0
  end
  if phase == "ending" then
    if (f - tStage) % 300 == 299 then n = n + 1; shot(string.format("ending_%02d", n)) end
    if mode ~= 0x0F then
      log("after the ending: " .. st()); shot("afterending")
      phase = "wait"; stage = nil; quest2 = true
    end
    if f > tStage + 20000 then log("the ending never finished: " .. st()); FAILS = FAILS + 1; done() end
    return
  end
  -- the second quest starts after the ending: a little of it
  if quest2 and playing() and r(0x28) == 2 then
    log("the second quest plays on: " .. st()); shot("quest2"); log("PASS"); done(); return
  end

  if not playing() or (r(0x126) & 1) == 0 then
    if phase == "step" and r(0x46C) ~= 4 and r(0x46C) ~= 6 and mode ~= 5 then phase = "wait" end
    if phase == "step" and (r(0x46C) == 4 or r(0x46C) == 6) then
      -- on the stairs, Castlevania moves her: that's progress
      still = 0
    else
      return
    end
  end

  if phase == "wait" or r(0x28) ~= stage then
    if stage and r(0x28) ~= stage then
      log(string.format("=== stage %d done in %d frames: %s", stage, f - tStage, st()))
      if stage >= last and stage ~= 18 then log("PASS"); done() return end
    end
    if r(0x28) ~= stage then savestate(string.format("play_%d", r(0x28))) end
    beginStage()
    n = 0
  end

  if (f - tStage) % 400 == 200 then n = n + 1; shot(string.format("%02d_%02d", stage, n)) end

  if HONEST then
    local en = r(0x118) * 256 + r(0x117)
    if en < lastEn then hitsTaken = hitsTaken + 1 end
    lastEn = en
  end

  if x() == lastx and r(0x46C) ~= 4 and r(0x12A) == 0 then still = still + 1 else still = 0 end
  lastx = x()

  if not step then fail("no route left") return end
  local kind = step[1]
  if kind == "go" then
    if math.abs(step[2] - x()) <= 6 and jump == 0 and r(0x10B) == 0 then log("    at " .. string.format("%04x", x()) .. " y " .. string.format("%02x", r(0x124))); nextstep() end
  elseif kind == "leap" then
    if hop > 44 and r(0x10B) == 0 then log(string.format("    leapt to %04x y %02x", x(), r(0x124))); hop = 0; nextstep() end
  elseif kind == "hop" then
    if hop > 44 and r(0x10B) == 0 then if os.getenv("PLAY_TRACE") then dumptrace(4) end; log(string.format("    hopped to %04x y %02x", x(), r(0x124))); hop = 0; nextstep() end
  elseif kind == "up" then
    if math.abs(step[2] - x()) <= 6 and r(0x10B) == 0 then log(string.format("    up at %04x y %02x", x(), r(0x124))); nextstep() end
  elseif kind == "stair" then
    local a = r(0x46C)
    if a == 4 or a == 6 then
      onStair = true
    elseif onStair then
      log(string.format("    stairs %d done: x %04x y %02x floor %d", step[2], x(), r(0x124), r(0x46)))
      nextstep()
    end
  elseif kind == "boss" then
    if r(0x48) ~= 0 and fightT == 0 then fightT = f; log("    boss locked: " .. st()) end
    if fightT ~= 0 and (f - fightT) % 600 == 300 then log("      " .. st()) end
  end
  if kind ~= "boss" and f - tStep > 5000 then fail("step " .. stepi .. " takes too long") return end
  if f - tStage > 40000 then fail("stage takes too long") end
  if still > 900 then fail("not moving") end
end
