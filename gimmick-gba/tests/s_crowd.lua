-- The first stage's boss, with Yumetaro standing still in its room, for tools/record.py
-- --crowd: the boss keeps throwing, and the frames are as heavy as they get. Nothing is
-- pressed in the fight, so a build without the NES's slowdown plays it the same way as
-- the NES, only faster, and its timing can be measured. Goes before s_record.lua.
local phase, t0 = "boot", 0
local function on_map() return r(0x40) == 0x1C or r(0x40) == 0x1B end
local function in_stage() return r(0x90) == 1 and not on_map() end

ON_NMI = function(f)
  if phase == "boot" then
    if r(0x90) == 1 and f > 600 then
      poke(0x1B, 0); poke(0x1C, 3); poke(0x346, 0); poke(0x104, 9)
      phase = "dying"; t0 = f
    end
  elseif phase == "dying" then
    if in_stage() and f > t0 + 60 then
      -- Into the boss's room, the way the tour's sweep gets there.
      poke(0xB8, 0x14); poke(0xA4, 0x33); poke(0xC2, 0)
      phase = "fight"; t0 = f
    end
  else
    -- At his most ($2B), not above it: past that, the status bar's loop at $E3E2 goes
    -- round 256 times a frame, and the NES lags all the time.
    if r(0x346) < r(0x2B) then poke(0x346, r(0x2B)) end
    if (f - t0) % 150 == 0 then
      local h = io.open(OUT .. "shot_" .. (f - t0) .. ".png", "wb")
      h:write(emu.takeScreenshot()); h:close()
    end
  end
end

PICK_INPUT = function(f)
  if phase ~= "fight" then
    return {start = (r(0x90) == 0 or r(0x90) >= 0xD0 or on_map()) and f % 60 < 5}
  end
  return {}
end
