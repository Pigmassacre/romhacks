-- Not a test of one thing: random buttons in every area, with Yumetaro flown along the level now
-- and then, watching every frame for what no route tries. Hits land; health and time are topped
-- up. Each kind of finding is logged the first few times per area, to out/test/fuzz_<seed>.log.
--
--   FUZZ_SEED=n    the random sequence
--   FUZZ_LEVELS=a,b,c  the areas (default: all), FUZZ_SLICE=i/n  every n'th of them
--   FUZZ_FRAMES=n  frames in each
local seed = tonumber(os.getenv("FUZZ_SEED") or "1")
local FRAMES = tonumber(os.getenv("FUZZ_FRAMES") or "5000")
math.randomseed(seed)
local names = {}
for n in (os.getenv("FUZZ_LEVELS") or ""):gmatch("[^,]+") do names[#names + 1] = n end
if #names == 0 then
  local si, sn = (os.getenv("FUZZ_SLICE") or "0/1"):match("(%d+)/(%d+)")
  for i, l in ipairs(levels()) do if (i - 1) % tonumber(sn) == tonumber(si) then names[#names + 1] = l.name end end
end
local FL = io.open(OUT .. "fuzz_" .. seed .. ".log", "w")
local function flog(s) FL:write(s .. "\n"); FL:flush() end

local li, phase, base = 0, "wait", nil
local held, until_, level = {}, 0, ""
local counts, totals = {}, {}
local function st()
  return string.format("x %d y %d xv %d yv %d air %d hp %d star %02x ride %d pipe %d halt %d/%d scr %d/%d die %d water %d climb %d", px(), py(), s8(rs("Player_XVel")), s8(rs("Player_YVel")), rs("Player_InAir"), rs("Gim_Health"), rs("Star_State"), rs("Gim_RideSlot"), rs("Level_PipeMove"), rs("Player_HaltGame"), rs("Player_HaltTick"), rs("Horz_Scroll_Hi") * 256 + rs("Horz_Scroll"), rs("Level_VertScroll"), rs("Player_IsDying"), rs("Player_InWater"), rs("Player_IsClimbing")) .. string.format(" flash %d lost %d kur %d frame %02x slot %d", rs("Player_FlashInv"), rs("Player_SuitLost"), rs("Player_Kuribo"), rs("Player_Frame"), rs("Star_Ridden"))
end
local function finding(kind, msg)
  counts[kind] = (counts[kind] or 0) + 1
  totals[kind] = (totals[kind] or 0) + 1
  if counts[kind] <= 3 then
    flog(string.format("!! %s %s (f %d): %s | %s", level, kind, F, msg or "", st()))
    if counts[kind] == 1 then
      local h = io.open(OUT .. string.format("fuzz_%s_%s.png", level, kind), "wb"); h:write(emu.takeScreenshot()); h:close()
    end
  end
end

emu.addMemoryCallback(function(a) finding("ramexec", string.format("pc %04x", a)) end, emu.callbackType.exec, 0x0000, 0x5FFF)
local spmin = 255
emu.addMemoryCallback(function()
  local s = emu.getState()["cpu.sp"]
  if s < spmin then spmin = s end
  if s < 0x60 then finding("stack", string.format("sp %02x", s)) end
end, emu.callbackType.exec, S["IntNMI"], S["IntNMI"])
emu.addMemoryCallback(function()
  local s = emu.getState()["cpu.sp"]
  local ret = r(0x101 + s) + 256 * r(0x102 + s)
  local why = "other"
  if rs("Level_TimerMSD") + rs("Level_TimerMid") + rs("Level_TimerLSD") == 0 then why = "time" end
  if rs("Gim_Health") == 0 then why = "hurt" end
  if rs("Player_SpriteY") >= 0xC0 and rs("Player_SpriteY") < 0xD0 then why = "pit" end
  if why == "other" then finding("death", string.format("from %04x sprite %d,%d", ret, rs("Player_SpriteX"), rs("Player_SpriteY"))) end
  totals["die_" .. why] = (totals["die_" .. why] or 0) + 1
end, emu.callbackType.exec, S["Player_Die"], S["Player_Die"])

local function randomize(f)
  local t = {}
  local k = math.random(100)
  if k < 50 then t.right = true elseif k < 72 then t.left = true end
  if math.random(100) < 10 then t.up = true end
  if math.random(100) < 10 then t.down = true end
  if math.random(100) < 45 then t.a = true end
  if math.random(100) < 35 then t.b = true end
  if math.random(1000) < 3 then t.start = true end
  held = t
  until_ = f + math.random(1, math.random(2, 60))
end
INPUT = function(f)
  if phase ~= "play" then return {} end
  if rs("Player_HaltGame") ~= 0 and math.random(100) < 10 then return {start = true} end
  return held
end

local function solid(x, y)
  if rs("Level_7Vertical") ~= 0 or y < 0 or y >= 0x1B0 or x < 0 then return false end
  local t = r(0x6000 + (x // 256) * 0x1B0 + (y // 16) * 16 + (x % 256) // 16)
  return t >= r(S["Tile_AttrTable"] + 4 + (t >> 6))
end

local last, lastc, stuckc, halted, inwall, floating, starAge, exitAt
local flying = 0
local function nextLevel()
  li = li + 1
  if li > #names then
    for k, v in pairs(totals) do flog(string.format("total %s %d", k, v)) end
    flog("spmin " .. string.format("%02x", spmin))
    FL:close()
    done()
    return
  end
  level = names[li]
  counts = {}
  local h = io.open(OUT .. "lv_" .. level .. ".mss", "rb")
  if not h then flog("no state " .. level); nextLevel(); return end
  local d = h:read("a"); h:close()
  emu.loadSavestate(d)
  F = 0; phase = "play"; until_ = 0; flying = 0; last = nil; lastc = -1; stuckc, halted, inwall, floating, starAge = 0, 0, 0, 0, 0
end
onexec(nextLevel)

FRAME = function(f)
  if phase ~= "play" then return end
  if f >= until_ then randomize(f) end
  ws("Level_TimerMSD", 3)
  if rs("Gim_Health") == 0 then ws("Gim_Health", 1) end
  if rs("Gim_Health") == 1 and f % 8 == 0 then ws("Gim_Health", 3) end

  -- left the level one way or another: start it again
  if rs("Level_ExitToMap") ~= 0 or rs("Level_Tileset") == 0 or rs("Player_IsDying") ~= 0 then
    if f >= FRAMES then phase = "next"; onexec(nextLevel); return end
    local d = f
    phase = "next"
    local h = io.open(OUT .. "lv_" .. level .. ".mss", "rb"); local s = h:read("a"); h:close()
    onexec(function() emu.loadSavestate(s); F = d; phase = "play"; last = nil end)
    return
  end
  if f >= FRAMES then phase = "next"; onexec(nextLevel); return end

  local x, y = px(), py()
  local c = rs("Counter_1")
  local paused = rs("Player_HaltGame") ~= 0
  -- the game has stopped
  if c == lastc then stuckc = stuckc + 1 else stuckc = 0 end
  lastc = c
  if stuckc == 200 and not paused then finding("hang", string.format("counter %02x", c)) end
  if rs("Player_HaltTick") ~= 0 then halted = halted + 1 else halted = 0 end
  if halted == 600 then finding("halted") end

  local moving = rs("Level_PipeMove") == 0 and rs("Level_JctCtl") == 0 and not paused and rs("Player_HaltTick") == 0
  if last and moving and last.ok then
    local dx, dy = math.abs(x - last.x), math.abs(y - last.y)
    if dx > 10 then finding("xjump", string.format("%d->%d", last.x, x)) end
    if dy > 12 then finding("yjump", string.format("%d->%d", last.y, y)) end
  end
  last = {x = x, y = y, ok = moving}

  -- in a wall for long
  if moving and rs("Level_7Vertical") == 0 and solid(x + 8, y + 24) and solid(x + 8, y + 18) then inwall = inwall + 1 else inwall = 0 end
  if inwall == 40 then finding("inwall", string.format("tile %02x", r(0x6000 + (x // 256) * 0x1B0 + ((y + 24) // 16) * 16 + (x % 256 + 8) // 16))) end

  -- hanging in the air
  if moving and rs("Player_InAir") ~= 0 and rs("Player_YVel") == 0 and rs("Player_IsClimbing") == 0 and rs("Player_InWater") == 0 and rs("Gim_RideSlot") == 0 and rs("Star_Ridden") == 0 then floating = floating + 1 else floating = 0 end
  if floating == 30 then finding("floating") end

  -- values out of range
  local hp, mx = rs("Gim_Health"), rs("Gim_MaxHealth")
  if hp > 6 or mx > 6 or hp > mx + 0 and hp ~= 3 then finding("health", string.format("%d of %d", hp, mx)) end
  if rs("Player_Suit") ~= 0 then finding("suit", tostring(rs("Player_Suit"))) end
  local ss = rs("Star_State")
  if not (ss == 0 or ss == 1 or (ss >= 0x7F and ss <= 0xA9) or (ss >= 0xD0 and ss < 0xE0)) then finding("starstate", string.format("%02x", ss)) end
  if ss == 1 then starAge = starAge + 1 else starAge = 0 end
  if starAge == 1500 then finding("starstuck", string.format("star %d,%d v %d,%d", rs("Star_XHi") * 256 + rs("Star_X"), rs("Star_YHi") * 256 + rs("Star_Y"), s8(rs("Star_XVel")), s8(rs("Star_YVel")))) end

  -- sprites using the tiles only Yumetaro's page has
  if f % 4 == 0 then
    local so = rs("Player_SprOff")
    for i = 0, 63 do
      local o = i * 4
      if (o < so or o >= so + 0x18) and r(0x200 + o) < 0xF0 then
        local t = r(0x201 + o)
        if t < 0x40 and t ~= 0x3D and t ~= 0x2D and t ~= 0x2F and t ~= 0x39 then
          local ids = {}
          for k = 0, 7 do ids[#ids + 1] = string.format("%02x", rs("Level_ObjectID", k)) end
          finding("lowtile", string.format("spr %d tile %02x at %d,%d attr %02x, objects %s", i, t, r(0x203 + o), r(0x200 + o), r(0x202 + o), table.concat(ids, " ")))
        end
      end
    end
  end

  -- fly along the level now and then, fast enough to see it but with the screen keeping up
  if f % 500 == 400 and moving and rs("Level_7Vertical") == 0 then flying = 90 end
  if flying > 0 then
    flying = flying - 1
    setx(math.min(x + 6, rs("Level_Width") * 256 + 200))
    sety(math.max(96, y - 4))
    ws("Player_YVel", 0); ws("Player_InAir", 1)
    last = nil; inwall = 0; floating = 0
end
end
