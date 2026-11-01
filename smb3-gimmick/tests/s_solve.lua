-- Not a test of one thing: tries to beat each level with controller inputs alone, by searching.
-- From the savestate at a level's start it tries short runs of buttons (walks, jumps, thrown
-- stars, rides on them, doors, pipes, waits) from the places it has reached, keeping a savestate
-- for each new place, until the level is cleared. Health and time are topped up, and nothing
-- else is touched. out/test/solve_<level>.txt gets the result and the buttons that won.
--
--   SOLVE_LEVELS=a,b,c  the levels (default: every area of out/levels.txt)
--   SOLVE_FRAMES=n      frames to spend on each level
--   SOLVE_SEED=n        the random sequence
--   SOLVE_RIDES=n       percent of tries that ride a star, for levels with walls to get over
local names = {}
for n in (os.getenv("SOLVE_LEVELS") or ""):gmatch("[^,]+") do names[#names + 1] = n end
if #names == 0 then for _, l in ipairs(levels()) do names[#names + 1] = l.name end end
local BUDGET = tonumber(os.getenv("SOLVE_FRAMES") or "60000")
math.randomseed(tonumber(os.getenv("SOLVE_SEED") or "1"))

local li = 0
local cells, order, used, won, area, deaths, maxx, junctions
local cur, plan, pi_, pleft, phase, runFrames, extra, startCell

local function ingame()
  return rs("Level_PipeMove") == 0 and rs("Level_JctCtl") == 0 and rs("Player_HaltTick") == 0 and rs("Player_HaltGame") == 0
end
local function key()
  local sc = 0
  if rs("Level_AScrlConfig") ~= 0 then sc = rs("Horz_Scroll_Hi") * 8 + rs("Horz_Scroll") // 32 end
  return string.format("%d:%d:%d:%d:%d", area, px() // 16, py() // 16, rs("Player_InAir") ~= 0 and 1 or 0, sc)
end

-- A macro is a list of {buttons, frames}. "until" macros keep going till the ground.
local D = {"R", "R", "R", "L", ""}
local function pick(t) return t[math.random(#t)] end
-- The end card, if it's on the screen; the nearest enemy, if any
local function target()
  local card, foe, fd = nil, nil, 1e9
  local sc = rs("Horz_Scroll_Hi") * 256 + rs("Horz_Scroll")
  for i = 0, 7 do
    if rs("Objects_State", i) == 2 and rs("Objects_SprHVis", i) == 0 then
      local x = rs("Objects_XHi", i) * 256 + rs("Objects_X", i)
      local id = rs("Level_ObjectID", i)
      if id == 0x41 or id == 0x52 or (id == 0x0E and rs("Level_GetWandState") == 2) then card = x
      elseif r(S["Object_AttrFlags"] + id) & 0x20 == 0 and i < 5 and math.abs(x - px()) < fd then foe, fd = i, math.abs(x - px()) end
    end
  end
  return card, foe
end

-- A door or pipe end near him: walk to it and go in
local function findway()
  if rs("Level_7Vertical") ~= 0 then return end
  local c0, r0 = (px() + 8) // 16, (py() + 24) // 16
  local best, bd
  for row = math.max(r0 - 8, 0), math.min(r0 + 6, 26) do
    for c = math.max(c0 - 14, 0), c0 + 14 do
      local t = r(0x6000 + (c // 16) * 0x1B0 + row * 16 + c % 16)
      if t == 0xAD or t == 0xAF or t == 0xB3 or t == 0xBD or t == 0x42 or t == 0x43 then
        local d = math.abs(c - c0) + math.abs(row - r0)
        if (not best or d < bd) and math.random(100) < 70 then best, bd = {c = c, r = row, t = t}, d end
      end
    end
  end
  return best
end

local RIDES = tonumber(os.getenv("SOLVE_RIDES") or "0")
local function macro()
  if math.random(100) <= RIDES then return "ride" end
  local card, foe = target()
  if math.random(100) <= 12 then
    local way = findway()
    if way then return {kind = "way", way = way} end
  end
  if card and math.random(100) <= 40 then return {kind = "seek", x = card} end
  if foe and math.random(100) <= 25 then return {kind = "aim", i = foe} end
  if math.random(100) <= 25 then return "go" end
  local k = math.random(100)
  local d = pick(D)
  if k <= 22 then return {{d, pick({6, 12, 24, 48, 96})}}
  elseif k <= 60 then
    local h = pick({3, 6, 10, 16, 24, 36})
    local a = pick({"R", "R", "L", ""})
    return {{a ~= "" and a or d, pick({0, 0, 8, 20})}, {"A " .. a, h}, {a, pick({10, 24, 40})}}
  elseif k <= 68 then return {{"B " .. d, pick({36, 44})}, {d, pick({6, 20, 40})}}
  elseif k <= 76 then return {{"B R", 36}, {"", pick({10, 20, 40})}, {"A", 16}, {"R", 30}}
  elseif k <= 90 then return "ride"
  elseif k <= 92 then return {{"D", 24}, {"", 40}}
  elseif k <= 94 then return {{"U", 24}, {"", 30}}
  elseif k <= 96 then return {{"U A", 20}, {"U " .. d, 24}, {"U", 40}}
  elseif k <= 97 then
    -- mash A: out of quicksand
    local p = {}
    for i = 1, 30 do p[#p + 1] = {"A " .. d, 2}; p[#p + 1] = {d, 2} end
    return p
  elseif k <= 98 then return {{"A " .. d, 10}, {"B " .. d, 36}, {d, 20}}
  else return {{"", pick({30, 60, 120})}} end
end

-- Throw a star, follow it till it rolls, jump on it, and jump from it
local ride = {}
local function rideInput()
  ride.t = ride.t + 1
  if ride.t < 37 then return pad("B " .. ride.d) end
  if ride.leap then
    ride.leap = ride.leap + 1
    if ride.leap > 34 then ride.done = true end
    if ride.leap <= ride.h then return pad("A " .. ride.dj) end
    return pad(ride.dj)
  end
  if rs("Star_State") ~= 1 or ride.t > 260 then ride.done = true; return {} end
  if rs("Star_Ridden") ~= 0 then
    ride.on = (ride.on or 0) + 1
    if ride.on > ride.wait then ride.leap = 0 end
    return {}
  end
  local dx = rs("Star_XHi") * 256 + rs("Star_X") - px()
  local t = {}
  if dx > 2 then t.right = true elseif dx < -2 then t.left = true end
  if rs("Player_InAir") ~= 0 then
    ride.air = (ride.air or 0) + 1
    if ride.air <= ride.jh then t.a = true end
    return t
  end
  ride.air = 0
  if rs("Star_Standable") ~= 0 and math.abs(dx) < ride.k and (rs("Star_Floor") ~= 0 or ride.any) then t.a = true end
  return t
end

-- Walk one way, hopping over walls and holes as they come
local TM = {}
local function solid(x, y)
  if rs("Level_7Vertical") ~= 0 or y < 0 or y >= 0x1B0 then return false end
  local t = r(0x6000 + (x // 256) * 0x1B0 + (y // 16) * 16 + (x % 256) // 16)
  return t >= r(S["Tile_AttrTable"] + (t >> 6))
end
local go = {}
local function goInput()
  go.t = go.t + 1
  if go.t > go.max then go.done = true end
  local x, y = px(), py()
  local t = {}
  t[go.d == 1 and "right" or "left"] = true
  if go.hold > 0 then
    go.hold = go.hold - 1
    t.a = true
    return t
  end
  if rs("Player_InAir") == 0 then
    local ahead = x + 8 + go.d * 20
    local gap = not (solid(ahead, y + 34) or solid(ahead, y + 50) or solid(ahead, y + 66))
    local wall = x == go.lastx
    go.lastx = x
    if gap or wall or math.random(100) <= 2 then
      t.a = true
      go.hold = pick({6, 16, 22, 30})
    end
  end
  return t
end

local way
local function wayInput()
  way.t = way.t + 1
  if way.t > 200 then way.done = true end
  local w_ = way.w
  local door = w_.t < 0x80
  local tx = w_.c * 16 + (door and 0 or 8)
  local dx = tx - px()
  local t = {}
  if math.abs(dx) > 3 then
    if dx > 0 then t.right = true else t.left = true end
    if rs("Player_InAir") == 0 and (px() == way.lx) then t.a = true end
    way.lx = px()
    if t.a or (rs("Player_InAir") ~= 0 and way.t % 40 < 20) then t.a = true end
    return t
  end
  -- there: in by whichever way it faces
  local above = r(0x6000 + (w_.c // 16) * 0x1B0 + (w_.r - 1) * 16 + w_.c % 16)
  if door then t.up = true
  elseif above < r(S["Tile_AttrTable"] + (above >> 6)) and py() + 32 <= w_.r * 16 + 4 then t.down = true
  else t.up = true; t.a = way.t % 30 < 20 end
  return t
end

-- Walk under the card and jump at it
local seek
local function seekInput()
  seek.t = seek.t + 1
  if seek.t > seek.max then seek.done = true end
  local t = {}
  local d = seek.x - px()
  if d > 2 then t.right = true elseif d < -2 then t.left = true end
  if math.abs(d) < seek.w then t.a = seek.t % 60 < 40 end
  return t
end
-- Face an enemy, jump if it's above, and throw a star at it
local aim
local function aimInput()
  aim.t = aim.t + 1
  if aim.t > 56 then aim.done = true end
  local d = rs("Objects_XHi", aim.i) * 256 + rs("Objects_X", aim.i) - px()
  local t = {}
  if aim.t < 37 then
    t.b = true
    if aim.t < 4 then if d > 0 then t.right = true else t.left = true end end
    if aim.t > 26 and aim.up then t.a = true end
  end
  return t
end

local function finish(result)
  local c = cur
  local h = io.open(OUT .. "solve_" .. names[li] .. ".txt", "w")
  h:write(string.format("%s %s frames %d cells %d maxx %d deaths %d junctions %d\n", names[li], result, used, #order, maxx, deaths, junctions))
  if result == "WON" then for _, s in ipairs(cur.path) do h:write(s .. "\n") end end
  h:close()
  log(string.format("%-20s %-5s frames %6d cells %5d maxx %5d deaths %d junctions %d", names[li], result, used, #order, maxx, deaths, junctions))
end

local nextLevel, startRun

startRun = function()
  if used > BUDGET then finish("-"); nextLevel(); return end
  -- newest-first bias: places rarely tried, and far along
  local best, bs = nil, -1
  for _ = 1, 10 do
    local c = order[math.random(#order)]
    local s = (c.x / (maxx + 1)) ^ 4 * 3 + c.area + 2 / (1 + c.visits) + math.random()
    if s > bs then best, bs = c, s end
  end
  cur = best
  cur.visits = cur.visits + 1
  emu.loadSavestate(cur.state)
  area = cur.area
  local m = macro()
  ride = {}
  if m == "ride" then ride = {t = 0, d = pick({"R", "R", "L"}), wait = pick({1, 4, 12, 30}), k = pick({12, 20, 28, 36, 48}), jh = pick({8, 14, 22, 40}), h = pick({10, 20, 34}), dj = pick({"R", "R", "L", ""}), any = math.random(100) < 25}; plan = "ride"
  elseif m == "go" then go = {t = 0, d = math.random(100) <= 85 and 1 or -1, hold = 0, max = pick({40, 80, 160}), done = false, seed = math.random(1 << 30)}; math.randomseed(go.seed); plan = "go"
  elseif type(m) == "table" and m.kind == "seek" then seek = {t = 0, x = m.x, max = pick({60, 120, 200}), w = pick({8, 16, 28}), done = false}; plan = "seek"
  elseif type(m) == "table" and m.kind == "way" then way = {t = 0, w = m.way, done = false}; plan = "way"
  elseif type(m) == "table" and m.kind == "aim" then aim = {t = 0, i = m.i, up = math.random(100) < 30, done = false}; plan = "aim"
  else plan = m end
  local scripted = type(plan) ~= "table"
  pi_, pleft, runFrames, extra = 1, (not scripted) and plan[1][2] or 0, 0, 0
  phase = "run"
  F = 0
end

nextLevel = function()
  li = li + 1
  if li > #names then done(); return end
  local h = io.open(OUT .. "lv_" .. names[li] .. ".mss", "rb")
  if not h then log("no savestate " .. names[li]); nextLevel(); return end
  local d = h:read("a"); h:close()
  cells, order, used, won, area, deaths, maxx, junctions = {}, {}, 0, false, 0, 0, 0, 0
  emu.loadSavestate(d)
  local st = emu.createSavestate()
  local c = {state = st, visits = 0, x = px(), area = 0, path = {}}
  cells[key()] = c; order[1] = c
  startRun()
end

local function planStr()
  if plan == "ride" then return string.format("ride %s w%d k%d jh%d h%d %s", ride.d, ride.wait, ride.k, ride.jh, ride.h, ride.dj) end
  if plan == "go" then return string.format("go %d %d", go.d, go.max) end
  if plan == "seek" then return "seek" end
  if plan == "way" then return "way" end
  if plan == "aim" then return "aim" end
  local t = {}
  for _, p in ipairs(plan) do t[#t + 1] = p[1] .. ":" .. p[2] end
  return table.concat(t, ",")
end

INPUT = function(f)
  if phase ~= "run" then return {} end
  if plan == "ride" then return rideInput() end
  if plan == "go" then return goInput() end
  if plan == "seek" then return seekInput() end
  if plan == "way" then return wayInput() end
  if plan == "aim" then return aimInput() end
  local p = plan[pi_]
  if not p then return {} end
  return pad(p[1])
end

local wasJct = 0
FRAME = function(f)
  if phase == "wait" then return end
  ws("Gim_Health", 3)
  ws("Level_TimerMSD", 3)
  used = used + 1; runFrames = runFrames + 1
  local j = rs("Level_JctCtl")
  if j ~= 0 and wasJct == 0 then area = area + 1; junctions = junctions + 1 end
  wasJct = j
  if px() > maxx and area == 0 then maxx = px() end
  -- cleared?
  if (rs("Level_ExitToMap") ~= 0 and rs("Map_ReturnStatus") == 0) or rs("Player_EndLevel") ~= 0 or rs("Level_GetWandState") ~= 0 or rs("Player_FallToKing") ~= 0 then
    cur.path = {table.unpack(cur.path)}
    cur.path[#cur.path + 1] = planStr()
    finish("WON")
    phase = "wait"
    onexec(nextLevel)
    return
  end
  if rs("Player_IsDying") ~= 0 or rs("Level_ExitToMap") ~= 0 then
    deaths = deaths + 1
    phase = "wait"
    onexec(startRun)
    return
  end
  if type(plan) == "table" then
    if pi_ <= #plan then
      pleft = pleft - 1
      while pleft <= 0 and pi_ <= #plan do
        pi_ = pi_ + 1
        pleft = plan[pi_] and plan[pi_][2] or 0
      end
    end
  end
  local over
  if plan == "ride" then over = ride.done elseif plan == "go" then over = go.done
  elseif plan == "seek" then over = seek.done elseif plan == "aim" then over = aim.done
  elseif plan == "way" then over = way.done
  else over = pi_ > #plan end
  -- wait for a pipe to finish, and for him to land: a place in the air is no place to start from
  local airborne = rs("Player_InAir") ~= 0 and rs("Player_InWater") == 0 and rs("Player_IsClimbing") == 0 and rs("Star_Ridden") == 0
  if over and (not ingame() or airborne) and extra < 240 then extra = extra + 1; return end
  if over and airborne then phase = "wait"; onexec(startRun); return end
  if over or runFrames > 400 then
    local k = key()
    local c = cells[k]
    if not c then
      local path = {table.unpack(cur.path)}
      path[#path + 1] = planStr()
      local x, a = px(), area
      phase = "wait"
      onexec(function()
        local n = {state = emu.createSavestate(), visits = 0, x = x, area = a, path = path}
        cells[k] = n
        order[#order + 1] = n
        startRun()
      end)
    else
      phase = "wait"
      onexec(startRun)
    end
  end
end
phase = "wait"
onexec(nextLevel)
