-- The world map, for tools/record.py --map: Start skips the intro and then starts on
-- the title, and the map opens and stays, with nothing pressed. Mesen's own picture
-- now and then shows how the NES draws it. Goes before s_record.lua.
local PRESS = {[300] = true, [600] = true}

ON_NMI = function(f)
  if f >= 600 and f % 20 == 0 then
    local h = io.open(OUT .. "shot_" .. f .. ".png", "wb")
    h:write(emu.takeScreenshot()); h:close()
  end
end

PICK_INPUT = function(f)
  for p in pairs(PRESS) do
    if f >= p and f < p + 5 then return {start = true} end
  end
  return {}
end
