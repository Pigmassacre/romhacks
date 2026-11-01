-- The second player in a level, for looking over: walks, jumps and summons the star, a shot every so often.
local pal = function(i) return emu.read(i, emu.memType.nesPaletteRam) end
local name = os.getenv("OH_LEVEL") or "W101L"
local L
for _, l in ipairs(levels()) do if l.name == name then L = l end end
local t
loadstate_raw("map", function()
  -- standing where the first player is, on 1-1: the second player's map position
  ws("Total_Players", 1); ws("Player_Current", 1); warp_to(L)
  ws("World_Map_Y", rs("World_Map_Y"), 1); ws("World_Map_XHi", rs("World_Map_XHi"), 1); ws("World_Map_X", rs("World_Map_X"), 1)
  ws("Map_Entered_Y", rs("Map_Entered_Y"), 1); ws("Map_Entered_XHi", rs("Map_Entered_XHi"), 1); ws("Map_Entered_X", rs("Map_Entered_X"), 1)
end)
INPUT = function(f)
  if not t then return (f % 8 < 3) and {a = true} or {} end
  return {}
end
-- The second player's turn reads the second controller, which the test runner has none of: this stands in for it
local BITS = {a = 0x80, b = 0x40, up = 0x08, down = 0x04, left = 0x02, right = 0x01}
local last = 0
emu.addMemoryCallback(function()
  if not t then return end
  local v = 0
  for k, b in pairs(BITS) do if second(F)[k] then v = v | b end end
  ws("Pad_Holding", v); ws("Pad_Input", v & ~last); last = v
end, emu.callbackType.exec, S["PRG031_FF11"], S["PRG031_FF11"])
function second(f)
  return pad(({"R", "R", "A R", "R", "B R", "A", "L", "A L", "B", "R"})[((f - t) // 25) % 10 + 1])
end
FRAME = function(f)
  if not t and f > 10 and rs("Player_XStart") ~= 0 then t = f + 45 end
  if t and f >= t and (f - t) % 18 == 0 then shot(string.format("%02d", (f - t) // 18)) end
  if t and f == t then log(string.format("bg %02x player %02x %02x %02x", pal(0), pal(17), pal(18), pal(19))) end
  if t and f == t + 270 then done() end
  if f == 1500 then check(false, "never entered"); done() end
end
