-- Paused for a good while as she dies. Her explosion's counter runs while the game
-- is paused; it once ran on to $80, which read as tiles still to load, and wrote
-- whatever came next in the ROM all over the tile memory and name tables, for good.
-- Falling in a pit on stage 4, then the tiles and the way back are as they were.
local PPU = emu.memType.nesPpuMemory
local phase, t0, base, stage, pressed = "load", 0, nil, 0, nil
local function hash()
  local h = 0
  for a = 0x160, 0x1FFF do h = (h * 31 + emu.read(a, PPU)) % 2147483647 end   -- not the HUD's digits
  return h
end
loadstate_raw("play_4", function() phase = "fall"; t0 = F end)
INPUT = function(f)
  if phase == "fall" and r(0x46C) == 8 and r(0x100) == 8 and not pressed then pressed = f; return {start = true} end
  if phase == "paused" and f == t0 + 500 then return {start = true} end
  return {}
end
FRAME = function(f)
  if phase == "fall" then
    if f == t0 + 5 then base = hash(); stage = r(0x28); w(0x118, 9); w(0x124, 0xD8); w(0x10B, 1) end
    if pressed and f == pressed + 4 then
      log(string.format("paused at action %d status %02x y %02x, $22 %02x", r(0x46C), r(0x100), r(0x124), r(0x22)))
      phase = "paused"; t0 = f
    end
  end
  if phase == "paused" and f == t0 + 480 then shot("paused") end
  if phase == "paused" and f == t0 + 510 then phase = "back"; t0 = f end
  if phase == "back" and r(0x18) ~= 5 then phase = "dead" end
  if phase == "back" and r(0x19) ~= 6 then phase = "dead" end
  if phase == "dead" and r(0x18) == 5 and r(0x19) == 6 and (r(0x126) & 1) == 1 and r(0x118) == 9 then
    shot("back")
    check(r(0x28) == stage, "back on the stage")
    check(hash() == base, "the tiles are as they were")
    phase = "after"; t0 = f
  end
  if phase == "after" and f == t0 + 120 then
    check(r(0x46C) == 0 and r(0x124) < 0xD0, string.format("standing on it (y %02x)", r(0x124)))
    check(hash() == base, "and still are")
    done()
  end
  if f > 3000 then check(false, "stuck in " .. phase); shot("stuck"); done() end
end
