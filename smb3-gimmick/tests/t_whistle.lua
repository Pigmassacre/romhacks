-- World 1 fortress's warp whistle: steps up the shaft let Yumetaro jump to the high door, which Mario
-- flew to (issue 11 of the old repository). Each hop is a real jump, from the floor to the door.
local HOPS = {{1448, 336, 1416, 288, "L"}, {1416, 288, 1464, 240, "R"}, {1450, 240, 1408, 192, "L"}, {1419, 192, 1460, 144, "R"}, {1495, 144, 1525, 96, "R"}, {1560, 96, 1600, 80, "R"}}
local i, phase, t = 1, "wait", 0
local function start()
  phase = "wait"
  onexec(function()
    local h = io.open(OUT .. "lv_W10FL.mss", "rb"); local d = h:read("a"); h:close()
    emu.loadSavestate(d); F = 0; t = 0; phase = "set"
  end)
end
start()
INPUT = function(f)
  if phase ~= "go" then return {} end
  local c = HOPS[i]
  local p = {}
  p[c[5] == "R" and "right" or "left"] = true
  if c[5] == "R" and px() >= c[3] then p.right = nil end
  if c[5] == "L" and px() <= c[3] then p.left = nil end
  if t < 24 then p.a = true end
  return p
end
FRAME = function(f)
  ws("Gim_Health", 3); ws("Gim_MaxHealth", 3)
  if phase == "set" then
    local c = HOPS[i]
    if f < 60 then
      setx(c[1]); sety(c[2]); ws("Player_YVel", 0)
      local sc = c[1] - 120
      ws("Horz_Scroll", sc % 256); ws("Horz_Scroll_Hi", sc // 256)
      for s = 0, 7 do if s ~= 6 then ws("Objects_State", 0, s) end end
    else phase = "go"; t = 0 end
    return
  end
  if phase ~= "go" then return end
  t = t + 1
  for s = 0, 7 do ws("Objects_State", 0, s) end
  if t > 8 and rs("Player_InAir") == 0 or t > 120 then
    local c = HOPS[i]
    check(py() == c[4], string.format("hop %d lands at %d,%d (wanted %d,%d)", i, px(), py(), c[3], c[4]))
    i = i + 1
    if i > #HOPS then done() else start() end
  end
end
