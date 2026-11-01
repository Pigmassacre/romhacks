-- Every map's battle rooms: stars kill the enemies, the treasure box comes down, and walking to it
-- gets back to the map with the panel cleared. (The box holds what the map object carried, and a
-- warp has none.)
local names = {}
for _, l in ipairs(levels()) do if l.name:match("HB[A-D]$") then names[#names + 1] = l.name end end
local i, phase, box = 0, "wait", nil
local dir
local function nextroom()
  i = i + 1
  if i > #names then done(); return end
  phase = "wait"
  onexec(function()
    local h = io.open(OUT .. "lv_" .. names[i] .. ".mss", "rb"); local d = h:read("a"); h:close()
    emu.loadSavestate(d); F = 0; phase = "fight"; box = nil
  end)
end
nextroom()
local function foe()
  for s = 0, 4 do
    local id = rs("Level_ObjectID", s)
    if rs("Objects_State", s) == 2 and id ~= 0x52 and id ~= 0 then return s end
  end
end
INPUT = function(f)
  if phase ~= "fight" then return {} end
  if box then
    local d = box - px()
    if d > 4 then return pad("R") elseif d < -4 then return pad("L") end
    return {}
  end
  local s = foe()
  local d = s and (rs("Objects_XHi", s) * 256 + rs("Objects_X", s) - px()) or 1
  local c = f % 70
  if c < 4 then return d > 0 and pad("B R") or pad("B L") end
  if c < 36 then return pad("B") end
  -- closer, and up onto whatever it's on
  if math.abs(d) > 48 then return d > 0 and pad("R A") or pad("L A") end
  return {}
end
FRAME = function(f)
  if phase ~= "fight" then return end
  ws("Gim_Health", 3); ws("Level_TimerMSD", 3)
  for s = 0, 4 do
    if rs("Level_ObjectID", s) == 0x52 and rs("Objects_State", s) ~= 0 and not box then box = rs("Objects_XHi", s) * 256 + rs("Objects_X", s); log(names[i] .. ": the box at " .. box) end
  end
  if rs("Level_ExitToMap") ~= 0 or rs("Level_Tileset") == 0 then
    check(rs("Map_ReturnStatus") == 0, names[i] .. ": back at the map, panel cleared, f " .. f)
    phase = "next"; onexec(nextroom)
    return
  end
  if f == 5000 then
    local s = foe()
    check(false, string.format("%s: still at %d, box %s, foe %s id %02x", names[i], px(), tostring(box), tostring(s), s and rs("Level_ObjectID", s) or 0)); shot(names[i]); phase = "next"; onexec(nextroom)
  end
end
