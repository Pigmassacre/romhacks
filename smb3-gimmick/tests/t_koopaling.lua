-- Each world's Koopaling: the star hurts it, three hits and the wand falls, Yumetaro takes it and
-- is off to the king. Stands in for stomps, which only bounce him off.
local world = tonumber(os.getenv("KOOPA_WORLD") or "1")
local phase = "fight"
local hits, lastv, wand, t = 0, nil, nil, 0
local function start()
  phase = "wait"
  onexec(function()
    local h = io.open(OUT .. "lv_W" .. world .. "Airship_BossL.mss", "rb"); local d = h:read("a"); h:close()
    emu.loadSavestate(d); F = 0; phase = "fight"; hits = 0; lastv = nil; wand = nil; t = 0
  end)
end
start()
local function boss()
  for i = 0, 4 do if rs("Level_ObjectID", i) == 0x0E and rs("Objects_State", i) ~= 0 then return i end end
end
INPUT = function(f)
  if phase ~= "fight" then return {} end
  if wand then
    local d = wand - px()
    local x = {}
    if d > 2 then x.right = true elseif d < -2 then x.left = true end
    x.a = f % 40 < 20
    return x
  end
  local b = boss()
  if not b then return {} end
  local d = rs("Objects_XHi", b) * 256 + rs("Objects_X", b) - px()
  local c = f % 70
  if c < 4 then return d > 0 and {right = true, b = true} or {left = true, b = true} end
  if c < 40 then return {b = true} end
  return {}
end
FRAME = function(f)
  if phase ~= "fight" then return end
  ws("Gim_Health", 3)
  local b = boss()
  if b then
    local v = rs("Objects_Var4", b)
    if lastv and v ~= lastv then hits = hits + 1; log(string.format("hit %d at f %d (var4 %d)", hits, f, v)) end
    lastv = v
  end
  -- with the Koopaling gone, its object is the wand
  if b and rs("Level_GetWandState") == 2 then wand = rs("Objects_XHi", b) * 256 + rs("Objects_X", b) end
  if rs("Player_FallToKing") ~= 0 or rs("Level_GetWandState") >= 3 then
    check(hits >= 3, string.format("world %d: wand taken after %d hits, f %d", world, hits, f))
    world = world + 1
    if world > 7 then done() else start() end
    return
  end
  if f > 20000 then check(false, string.format("world %d: no wand (hits %d, boss %s, wand %s, at %d,%d)", world, hits, tostring(b), tostring(wand), px(), py())); world = world + 1; if world > 7 then done() else start() end end
end
