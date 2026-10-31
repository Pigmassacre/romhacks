-- The 2-player battle, for looking over: two players play with random buttons.
local games = tonumber(os.getenv("VS_GAME") or "0")
loadstate_raw("map", function() ws("Total_Players", 1); ws("Map_Enter2PFlag", 1); ws("Map_2PVsGame", games) end)
local n = 0
INPUT = function(f)
  if f < 40 then return (f % 8 < 3) and {a = true} or {} end
  return pad(({"R", "L", "A R", "A L", "R", "B"})[(f // 40) % 6 + 1])
end
FRAME = function(f)
  if f % 200 == 0 then n = n + 1; shot(string.format("%02d", n)); log(string.format("f %d tileset %d", f, rs("Level_Tileset"))) end
  if f == 2400 then done() end
end
