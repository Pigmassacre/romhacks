-- Not a test of one thing: random buttons on every stage, with Samus flown to
-- random places and stairs now and then, watching for what no route tries.
-- Hits land; energy, lives and time are topped up. Each kind of finding is
-- logged the first few times, with what led to it.
--
--   FUZZ_SEED=n    the random sequence
--   FUZZ_FROM=n, FUZZ_TO=n   the stages
--   FUZZ_FRAMES=n  frames on each stage
local seed = tonumber(os.getenv("FUZZ_SEED") or "1")
local from = tonumber(os.getenv("FUZZ_FROM") or "1")
local to = tonumber(os.getenv("FUZZ_TO") or "18")
local FRAMES = tonumber(os.getenv("FUZZ_FRAMES") or "6000")
math.randomseed(seed)
local FL = io.open(OUT .. "fuzz_" .. seed .. ".log", "w")
local function flog(s) FL:write(s .. "\n"); FL:flush() end

local src = io.open(REPO .. "/tests/s_exits.lua"):read("a")
local STAIRS = load(src:match("STAIRS = (%b{})") and ("return " .. src:match("STAIRS = (%b{})")))()

local EXITS = load("return " .. src:match("EXITS = (%b{})"))()
local SCREEN0 = {[0]=0,0,0,0,0,1,0,0,1,0,0,0,0,1,0,0,1,0,1,0}
local function cell(px, y)
  if y < 0x30 or y >= 0xE0 then return 0 end
  local X = (px % 256) // 8
  local idx = (X >> 2) + ((y & 0xF8) - 0x30)
  local sc = SCREEN0[r(0x28)] + (px >> 8)
  return (r(0x5A0 + idx + ((sc & 1) == 1 and 0xB0 or 0)) >> (2 * ((X ~ 3) & 3))) & 3
end
local function x() return r(0x122) + 256 * r(0x123) end
local function scroll() return r(0x2E) + 256 * r(0x2F) end
local function st() return string.format("stage %d floor %d mode %02x/%02x act %d status %02x x %04x sx %02x y %02x scr %04x ride %02x lock %d en %x%02x inv %02x", r(0x28), r(0x46), r(0x18), r(0x19), r(0x46C), r(0x100), x(), r(0x38C), r(0x124), scroll(), r(0x12A), r(0x48), r(0x118), r(0x117), r(0x113)) end

local RING, ringi = {}, 0
local counts, total = {}, 0
local function finding(kind, msg)
  counts[kind] = (counts[kind] or 0) + 1
  total = total + 1
  if counts[kind] <= 4 then
    flog(string.format("!! %s (f %d): %s | %s", kind, F, msg or "", st()))
    if counts[kind] == 1 then
      for i = math.max(1, ringi - 12), ringi do if RING[i % 32] then flog("     " .. RING[i % 32]) end end
      local h = io.open(OUT .. string.format("fuzz_%d_%s_%d.png", seed, kind, r(0x28)), "wb"); h:write(emu.takeScreenshot()); h:close()
    end
  end
end

-- CPU-level watches
local nmis, lates = 0, 0
emu.addMemoryCallback(function()
  nmis = nmis + 1
  if nmis % 64 == 0 then
    local s = emu.getState()
    if s["cpu.sp"] < 0xD0 then finding("stack", string.format("sp %02x", s["cpu.sp"])) end
  end
  local n = r(0x20)
  buflen = n
  local y, ents = 0, {}
  while r(0x700 + y) ~= 0 and #ents < 12 and y < 256 do
    local inc, hi, lo = r(0x700 + y), r(0x701 + y), r(0x702 + y)
    local yy, c = y + 3, 0
    while yy < 300 do
      local b = r(0x700 + yy % 256); yy = yy + 1
      if b == 0xFF then
        if r(0x700 + yy % 256) < 3 then break end
      end
      c = c + 1
    end
    ents[#ents + 1] = string.format("%02x@%02x%02x+%d", inc, hi, lo, c)
    y = yy
  end
  bufents = table.concat(ents, " ")
  if n >= 0xCF and r(0x18) == 5 and r(0x19) == 6 then finding("bufover", string.format("buffer %02x start %02x [%s]", n, r(0x128), bufents or "")) end
end, emu.callbackType.exec, 0xC052, 0xC052)
emu.addMemoryCallback(function(a) finding("ramexec", string.format("pc %04x", a)) end, emu.callbackType.exec, 0x0000, 0x1FFF)
local splitstages = {}
prevsplit = nil
emu.addMemoryCallback(function(a, v)
  if v ~= 0 and (r(0x126) & 0x40) ~= 0 and r(0x18) == 5 then
    local l = emu.getState()["ppu.scanline"]
    if l >= 0 and l < 240 and l ~= 44 then
      finding("splitline", string.format("line %d, buffer %02x [%s], prev %s flash %02x", l, buflen or 0, bufents or "", tostring(prevsplit), r(0x15D)))
      local ls = r(0x28)
      splitstages[ls] = (splitstages[ls] or 0) + 1
    end
    prevsplit = l
  end
end, emu.callbackType.write, 0x2001, 0x2001)

-- what she does
local stage, phase = from, "warp"
local held, until_, flying, flyTo, flyY, stair = {}, 0, false, nil, nil, nil
local died, stageStart = false, 0
local function warp()
  w(0x28, stage); w(0x29, stage); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9); w(0x5B, 0); w(0x113, 0)
  w(0x1C0, 0)
  died = false; phase = "warp"
end
loadstate_raw("castle", warp)

local function randomize(f)
  local t = {}
  local k = math.random(100)
  if k < 35 then t.right = true elseif k < 70 then t.left = true end
  if math.random(100) < 12 then t.up = true end
  if math.random(100) < 12 then t.down = true end
  if math.random(100) < 35 then t.a = true end
  if math.random(100) < 40 then t.b = true end
  if math.random(100) < 3 then t.select = true end
  if math.random(1000) < 8 then t.start = true end
  held = t
  until_ = f + math.random(1, math.random(2, 60))
  if r(0x22) ~= 0 and math.random(100) < 50 then held = {start = true}; until_ = f + 2 end
end
INPUT = function(f)
  if phase ~= "play" then return (r(0x22) ~= 0 and f % 8 == 0) and {start = true} or {} end
  if r(0x18) == 0x0D then return {start = f % 60 < 3} end
  if flying then local t = flyTo > x() and pad("R") or pad("L"); t.a = f % 16 < 2; t.b = f % 7 == 0; return t end
  return held
end

local last = {}
local still, inwall, hidden, modeSince, modeWas, nmiSeen = 0, 0, 0, 0, -1, 0
local cleanSince = 0
FRAME = function(f)
  local mode, aux = r(0x18), r(0x19)
  local inplay = mode == 5 and aux == 6
  ringi = ringi + 1
  RING[ringi % 32] = string.format("f %d %s btn %s%s%s%s%s%s", f, st(), held.left and "L" or "", held.right and "R" or "", held.up and "U" or "", held.down and "D" or "", held.a and "A" or "", held.b and "B" or "")
  if phase ~= "warp" and stage then
    w(0x118, 9); w(0x2A, 9); w(0x43, 4)
  end
  if mode == 0x0D then return end

  if nmis == nmiSeen and f > 5 and mode == 5 and aux == 6 then finding("nonmi") end
  nmiSeen = nmis

  if phase == "warp" then
    if mode == 6 then died = true end
    if not died and mode == 5 then w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x5B, 0); w(0x113, 0); w(0x28, stage); w(0x29, stage) end
    if died and inplay and r(0x28) == stage and (r(0x126) & 1) == 1 then
      phase = "play"; stageStart = f; until_ = 0; flying = false; last = {}; cleanSince = f
      flog(string.format("--- stage %d (f %d): %s", stage, f, st()))
    end
    return
  end

  -- the mode can change under her; the stage may move on by itself
  local mm = mode * 256 + aux
  if mm ~= modeWas then modeWas = mm; modeSince = f end
  local limit = (mode == 0x0F) and 20000 or 2500
  if mode ~= 5 and f - modeSince > limit then finding("modestuck", string.format("mode %02x for %d frames", mode, f - modeSince)); warp(); return end
  if mode == 5 and aux ~= 6 and f - modeSince > 1500 and r(0x1A) == last.fc then finding("hang") end
  last.fc = r(0x1A)

  if f - stageStart > FRAMES or (mode == 0x0F) then
    w(0x1C0, 0)
    stage = stage + 1
    if stage > to then
      local keys = {}
      for k, v in pairs(counts) do keys[#keys + 1] = k .. "=" .. v end
      local ss = {}
      for k, v in pairs(splitstages) do ss[#ss + 1] = k .. ":" .. v end
      flog("=== done: " .. total .. " findings: " .. table.concat(keys, " ") .. " | split by stage " .. table.concat(ss, " "))
      FL:close(); log("PASS"); done(); return
    end
    warp(); return
  end

  if not inplay then
    cleanSince = f; last.x = nil
    if flying then flying = false; w(0x1C0, 0) end
    if f > until_ then randomize(f) end
    return
  end
  if r(0x28) ~= stage then stage = r(0x28); cleanSince = f; last.x = nil end   -- walked on

  -- flying: the tests' way of getting anywhere
  if flying then
    w(0x1C0, 0x80); w(0x124, flyY); w(0x10B, 0); w(0x109, 0)
    cleanSince = f; last.x = nil
    local d = flyTo - x()
    local clear = true
    for _, dy in ipairs({-16, -8, 0, 8}) do for _, dx in ipairs({-8, 0, 8}) do if cell(x() + dx, flyY + dy) ~= 0 then clear = false end end end
    if (math.abs(d) <= 3 or f > until_) and clear then
      w(0x1C0, 0); flying = false; until_ = 0
      if stair then held = stair; until_ = f + 90; stair = nil end
    end
    return
  end

  if f > until_ and r(0x1F) == 0 then
    local k = math.random(100)
    local e = EXITS[stage]
    if k == 5 and e and e[1] == r(0x46) then
      -- to the stage's end, with buttons going
      flying = true; flyY = e[2] + 1 - 0x18
      flyTo = (e[3] >= 0x80) and x() + 2000 or math.max(9, 0)
      until_ = f + 500
    elseif k == 6 and r(0x48) ~= 0 then
      w(0x1A9, 1)
    elseif k <= 2 then
      flying = true
      flyY = 0x38 + math.random(0, 18) * 8
      flyTo = math.max(8, x() + math.random(-500, 500))
      until_ = f + 400
    elseif k <= 4 and STAIRS[stage] then
      local here = {}
      for _, e in ipairs(STAIRS[stage]) do if e[2] == r(0x46) then here[#here + 1] = e end end
      if #here > 0 then
        local e = here[math.random(#here)]
        flying = true; flyTo = e[4] + ({0, -1, 5, 2})[e[3] + 1] + math.random(-6, 6); flyY = e[1] + 1 - 0x14
        until_ = f + 400
        stair = e[3] >= 2 and pad("D") or pad("U")
      end
    else randomize(f) end
  end

  -- what should always be so, a little after anything big
  if f - cleanSince < 6 then
    last.x, last.y, last.scr = x(), r(0x124), scroll()
    return
  end
  local paused = r(0x1F) ~= 0 or r(0x22) ~= 0
  local a, stat, px, py, scr = r(0x46C), r(0x100), x(), r(0x124), scroll()
  if last.x then
    if math.abs(px - last.x) > 5 then finding("xjump", string.format("%04x to %04x", last.x, px)) end
    if math.abs(py - last.y) > 14 and a ~= 8 then finding("yjump", string.format("%02x to %02x", last.y, py)) end
    if math.abs(scr - last.scr) > 4 then finding("scrolljump", string.format("%04x to %04x", last.scr, scr)) end
  end
  last.x, last.y, last.scr = px, py, scr
  local on = (px - scr)
  if on < 0 or on > 255 then finding("offscreen", string.format("x-scroll %d", on)) end
  if a <= 3 and on >= 0 and on < 256 and math.abs(r(0x38C) - on) > 2 then finding("screenx", string.format("screen x %02x, level says %02x", r(0x38C), on)) end
  if a > 9 then finding("action", "action " .. a) end
  if stat > 8 and stat ~= 0xFF then finding("status", "status " .. stat) end
  if r(0x46) > 1 then finding("floor", "floor " .. r(0x46)) end
  if r(0x1BE) ~= 0 and false then finding("depth") end

  -- in a wall
  if a ~= 4 and a ~= 6 and a ~= 8 and stat ~= 3 and py >= 0x38 and py < 0xD8 and cell(px, py) ~= 0 and cell(px, py - 8) ~= 0 then
    inwall = inwall + 1
    if inwall == 20 then finding("inwall") end
  else inwall = 0 end

  -- stuck: pressing things, going nowhere, with room to
  if not paused and last.sx == px and last.sy == py then
    still = still + 1
    if still == 900 then finding(r(0x1A) == last.stuckfc and "frozen" or "stuck") end
    if still == 800 then last.stuckfc = r(0x1A) end
    if still >= 900 and still < 906 then
      local c = emu.getState()
      local b = {}
      for i = 0, 15 do b[#b + 1] = string.format("%02x", r(0x100 + c["cpu.sp"] + 1 + i)) end
      flog(string.format("   pc %04x sp %02x 1B %02x 1A %02x 20 %02x start %02x 18/19 %02x/%02x 7F %02x depth %02x bank %02x stack %s 1F %02x 22 %02x 7E %02x", c["cpu.pc"], c["cpu.sp"], r(0x1B), r(0x1A), r(0x20), r(0x128), r(0x18), r(0x19), r(0x7F), r(0x1BE), r(0x27), table.concat(b, " "), r(0x1F), r(0x22), r(0x7E)))
    end
  else still = 0 end
  last.sx, last.sy = px, py

  -- the screen
  if not paused then
    local S = emu.memType.nesSpriteRam
    if emu.read(0, S) ~= 0x27 or emu.read(3, S) ~= 8 or emu.read(1, S) ~= 0xFF then finding("sprite0", string.format("%02x %02x %02x %02x", emu.read(0, S), emu.read(1, S), emu.read(2, S), emu.read(3, S))) end
    if emu.read(0x20A1, emu.memType.nesPpuDebug or emu.memType.ppuDebug or emu.memType.nesPpuMemory) ~= 0xFE then finding("dot") end
    local n = 0
    for i = 17, 63 do
      local y, t = emu.read(i * 4, S), emu.read(i * 4 + 1, S)
      if y < 0xEF and t < 0x70 then n = n + 1 end
    end
    if n == 0 and a ~= 8 and r(0x113) == 0 and r(0x5B) == 0 and py < 0xE0 and stat ~= 3 then
      hidden = hidden + 1
      if hidden == 12 then finding("invisible") end
    else hidden = 0 end
    local hud = emu.read(9 * 4, S)
    if hud ~= 0x19 then last.hud = (last.hud or 0) + 1; if last.hud == 5 then finding("nohud", string.format("sprite 9 y %02x", hud)) end else last.hud = 0 end
  end
end
