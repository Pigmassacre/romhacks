-- The ending as the second player saw it, for looking over.
loadstate_raw("lv_W101L", function() ws("Total_Players", 1); ws("Player_Current", 1); ws("Player_RescuePrincess", 1); ws("Level_ExitToMap", 1) end)
INPUT = function(f) if f % 200 < 3 then return {a = true} end return {} end
FRAME = function(f)
  if f == 3 then ws("Level_ExitToMap", 1) end
  if f % 150 == 0 then shot(string.format("%03d", f // 150)) end
  if f == 150 * 60 then done() end
end
