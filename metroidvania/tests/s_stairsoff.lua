-- Not a test: every staircase, started with the camera at each side of the
-- middle (Samus flown in from the left leaves the screen behind her, from the
-- right ahead of her). Simon always starts at the middle; she doesn't. Logs
-- anything off: a jump of the screen or of her, Castlevania's idea of her x
-- differing from hers, not standing afterwards, a death. A staircase that didn't
-- start is tried again a little to the side, the windows being narrow; those
-- that never do are listed (stage 17's top at y $30 is only passed through, on
-- the way between floors).
local src = io.open(REPO .. "/tests/s_exits.lua"):read("a")
local STAIRS = load("return " .. src:match("STAIRS = (%b{})"))()
local stage = tonumber(os.getenv("ST_FROM") or "1")
local last = tonumber(os.getenv("ST_TO") or "18")
local function x() return r(0x122) + 256 * r(0x123) end
local function scroll() return r(0x2E) + 256 * r(0x2F) end
local function st() return string.format("act %d x %04x sx %02x y %02x scr %04x mode %02x/%02x stage %d floor %d accy %02x", r(0x46C), x(), r(0x38C), r(0x124), scroll(), r(0x18), r(0x19), r(0x28), r(0x46), r(0x10B)) end
local todo, phase, t0, e, dir, side, died = nil, "next", 0, nil, nil, 1, false
-- Stairs that were seen to change floors, to get to the rest of a stage. Flying
-- is up high: stage 14's floor 1 only scrolls on from screen 4 above y $60.
local link, linking, floor0 = {}, false, 0
local FLY = 0x50
local lastx, blocked, nudge = 0, 0, 0
local bad, runs = 0, 0
local function flag(msg) bad = bad + 1; log(string.format("!! stage %d (y %02x f%d t%d x %04x) from %s: %s | %s", stage, e[1], e[2], e[3], e[4], side > 0 and "left" or "right", msg, st())); shot(string.format("%02d_%04x", stage, e[4])) end
local maxds, maxdx, maxoff, lx, ls, climbed
local function towarp() phase = "towarp"; died = false end
local function newstage()
  todo = {}
  link = {}
  for _, en in ipairs(STAIRS[stage] or {}) do todo[#todo + 1] = {en, 1}; todo[#todo + 1] = {en, -1} end
end
newstage()
local function pick()
  for i, t in ipairs(todo) do
    if t[1][2] == r(0x46) then table.remove(todo, i); e, side = t[1], t[2]; return true end
  end
  return false
end
loadstate_raw("castle", function() towarp() end)
INPUT = function(f)
  if phase == "fly" or phase == "walkin" then return dir end
  if phase == "press" and f > t0 + 2 then return e[3] >= 2 and pad("D") or pad("U") end
  return {}
end
FRAME = function(f)
  if phase ~= "warp" and phase ~= "towarp" then w(0x118, 9); w(0x5B, 0x40); w(0x43, 4); w(0x2A, 9) end
  if f > 400000 then log("FAIL timeout " .. phase); done() end
  if r(0x18) == 6 then
    if phase == "press" or phase == "after" then flag("died"); phase = "next" end
    died = true
  end
  if phase == "towarp" and (r(0x18) == 5 or r(0x18) == 8) then
    w(0x28, stage); w(0x29, stage); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9); w(0x5B, 0); w(0x113, 0)
    if r(0x18) == 5 then phase = "warp" end
  end
  if phase == "warp" and died and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == stage and (r(0x126) & 1) == 1 then phase = "choose" end
  if phase == "next" then
    if r(0x18) == 5 and r(0x19) == 6 and r(0x28) == stage then phase = "choose" else towarp() end
  end
  if phase == "choose" then
    if pick() then phase = "fly"; t0 = f; linking = false
    elseif #todo > 0 and link[r(0x46)] and (todo.links or 0) < 12 then
      todo.links = (todo.links or 0) + 1
      e, side = link[r(0x46)], 1; phase = "fly"; t0 = f; linking = true
    elseif #todo > 0 and not todo.retried then todo.retried = true; towarp()
    else
      for _, t in ipairs(todo) do log(string.format("stage %d: not reached y %02x f%d x %04x", stage, t[1][1], t[1][2], t[1][4])) end
      stage = stage + 1
      if stage > last then log(string.format("%d runs, %d findings", runs, bad)); log("PASS"); done(); return end
      newstage(); towarp()
    end
  end
  if phase == "fly" then
    local tx = e[4] + ({0, -1, 5, 2})[e[3] + 1] + nudge - side * 0x40
    w(0x1C0, 0x80); w(0x124, FLY); w(0x10B, 0); w(0x109, 0)
    local d = tx - x()
    dir = d > 0 and pad("R") or pad("L")
    -- (or as far as the stage goes that way)
    if x() == lastx then blocked = blocked + 1 else blocked = 0 end
    lastx = x()
    if math.abs(d) <= 3 or blocked > 30 then dir = side > 0 and pad("R") or pad("L"); phase = "fly2"; blocked = 0 end
    if f > t0 + 3000 then log("couldn't fly: " .. st()); phase = "next" end
  end
  if phase == "fly2" then
    -- on through, the way the camera trails, to the stair
    local tx = e[4] + ({0, -1, 5, 2})[e[3] + 1]
    w(0x1C0, 0x80); w(0x124, FLY); w(0x10B, 0); w(0x109, 0)
    phase = "walkin"
  end
  if phase == "walkin" then
    local tx = e[4] + ({0, -1, 5, 2})[e[3] + 1] + nudge
    w(0x1C0, 0x80); w(0x124, FLY); w(0x10B, 0); w(0x109, 0)
    if (tx - x()) * side <= 1 then
      w(0x122, tx % 256); w(0x123, tx // 256); w(0x124, e[1] + 1 - 4); w(0x1C0, 0)
      phase = "land"; t0 = f
    end
    if f > t0 + 3000 then log("couldn't walk in: " .. st()); phase = "next" end
  end
  if phase == "land" and f == t0 + 25 then floor0 = r(0x46); phase = "press"; t0 = f; maxds, maxdx, maxoff, lx, ls, climbed = 0, 0, 0, x(), scroll(), false; runs = runs + 1 end
  if phase == "press" then
    local a, m = r(0x46C), r(0x18)
    if a == 4 then climbed = true end
    if a == 4 and r(0x19) == 6 then
      local world = r(0x40) + 256 * r(0x41)
      local screen = r(0x38C) + scroll()
      maxoff = math.max(maxoff, math.abs(world - screen))
    end
    if m == 5 and r(0x19) ~= 6 then ls = nil end
    if m == 5 and r(0x19) == 6 then
      ls = ls or scroll()
      if ls then maxds = math.max(maxds, math.abs(scroll() - ls)); maxdx = math.max(maxdx, math.abs(x() - lx)) end
      ls = scroll(); lx = x()
    end
    if m ~= 5 then log(string.format("stage %d (y %02x f%d x %04x) from %s: mode %02x at scroll %04x sx %02x", stage, e[1], e[2], e[4], side > 0 and "left" or "right", m, scroll(), r(0x38C))); towarp()
    elseif climbed and a == 0 then phase = "after"; t0 = f
      nudge = 0
      if maxds > 4 or maxdx > 8 then flag(string.format("jumped: screen %d, her %d", maxds, maxdx)) end
      if maxoff > 1 then flag(string.format("Castlevania's x differs by %d", maxoff)) end
    elseif f > t0 + (climbed and 700 or 120) then
      if climbed then flag("still on the stairs"); nudge = 0; phase = "next"
      elseif nudge > -4 then nudge = nudge - 2; phase = "fly"; t0 = f
      else log(string.format("stage %d (y %02x f%d t%d x %04x) from %s: didn't start: %s", stage, e[1], e[2], e[3], e[4], side > 0 and "left" or "right", st())); nudge = 0; phase = "next" end
    end
  end
  if phase == "after" and f == t0 + 120 then
    if r(0x46) ~= floor0 then link[floor0] = e end
    local sx = (x() - scroll())
    if r(0x10B) ~= 0 then flag("not standing") end
    if r(0x38C) ~= sx % 256 then flag(string.format("screen x %02x, level %02x", r(0x38C), sx % 256)) end
    if sx < 0 or sx > 255 then flag("off the screen") end
    phase = "choose"
  end
end
