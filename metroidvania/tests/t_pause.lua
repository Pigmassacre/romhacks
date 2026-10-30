-- Pausing: Castlevania's Start stops everything. Samus, her shots and her
-- HUD stay as they were, and buttons pressed while paused do nothing.
local x0, y0, shot0, missile0, hud0, time0
local function sprites(a, n) local t = {} for i = a, a + n - 1 do t[#t + 1] = emu.read(i, emu.memType.nesSpriteRam) end return table.concat(t, ",") end
local S = emu.memType.nesSpriteRam
loadstate_raw("castle", function() end)
INPUT = function(f)
  if f == 10 or f == 121 then return pad("B") end
  if f == 12 or f == 200 then return pad("S") end
  if f >= 30 and f < 190 then
    if f == 60 then return pad("A") end
    if f == 70 then return pad("E") end
    if f == 80 then return pad("B") end
    return pad("R")
  end
  return {}
end
FRAME = function(f)
  if f == 25 then
    x0, y0, shot0 = r(0x122), r(0x124), r(0x7CF) + r(0x7D0) + r(0x7D1)
    missile0, hud0, time0 = r(0x11B), sprites(0x1C, 40), r(0x42)
    shot("paused")
  end
  if f == 180 then
    check(r(0x122) == x0 and r(0x124) == y0, "she doesn't move while paused")
    check(r(0x7CF) + r(0x7D0) + r(0x7D1) == shot0, "no new shots while paused")
    check(r(0x11B) == missile0, "Select does nothing while paused")
    check(r(0x42) == time0, "the time stands still")
    check(sprites(0x1C, 40) == hud0, "the HUD stays")
    check(r(0x18) == 5 and r(0x19) == 6, "still in play")
  end
  if f == 260 then
    check(r(0x42) ~= time0 or r(0x43) ~= 0, "unpaused")
    check(r(0x122) == x0 and r(0x124) == y0, "held right was let go: she stands where she was")
    shot("unpaused")
    done()
  end
end
