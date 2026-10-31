-- Not a test of one thing: tries to beat each level with controller inputs alone, by searching.
-- From the savestate at a level's start it tries short runs of buttons (walks, jumps, thrown
-- stars, rides on them, doors, pipes, waits) from the places it has reached, keeping a savestate
-- for each new place, until the level is cleared. Health and time are topped up, and nothing
-- else is touched. out/test/solve_<level>.txt gets the result and the buttons that won.
--
--   SOLVE_LEVELS=a,b,c  the levels (default: every area of out/levels.txt)
--   SOLVE_FRAMES=n      frames to spend on each level
--   SOLVE_SEED=n        the random sequence
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
local function macro()
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
  elseif k <= 93 then return {{"D", 24}, {"", 40}}
  elseif k <= 96 then return {{"U", 24}, {"", 30}}
  elseif k <= 97 then return {{"U A", 20}, {"U " .. d, 24}}
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
  else plan = m end
  pi_, pleft, runFrames, extra = 1, (plan ~= "ride" and plan ~= "go") and plan[1][2] or 0, 0, 0
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
  local t = {}
  for _, p in ipairs(plan) do t[#t + 1] = p[1] .. ":" .. p[2] end
  return table.concat(t, ",")
end

INPUT = function(f)
  if phase ~= "run" then return {} end
  if plan == "ride" then return rideInput() end
  if plan == "go" then return goInput() end
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
  if plan ~= "ride" and plan ~= "go" then
    if pi_ <= #plan then
      pleft = pleft - 1
      while pleft <= 0 and pi_ <= #plan do
        pi_ = pi_ + 1
        pleft = plan[pi_] and plan[pi_][2] or 0
      end
    end
  end
  local over = (plan == "ride" and ride.done) or (plan == "go" and go.done) or (plan ~= "ride" and plan ~= "go" and pi_ > #plan)
  if over and (not ingame()) and extra < 240 then extra = extra + 1; return end
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
