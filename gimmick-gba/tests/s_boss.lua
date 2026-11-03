-- The first stage's boss, fought for a while, for tools/record.py --boss: it throws
-- a lot at once, which makes for the heaviest frames. It warps to the stage's last
-- checkpoint, keeps Yumetaro's health up, and goes before s_record.lua.
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
    if r(0x346) < 3 then poke(0x346, 3) end
    if (f - t0) % 150 == 0 then
      local h = io.open(OUT .. "shot_" .. (f - t0) .. ".png", "wb")
      h:write(emu.takeScreenshot()); h:close()
    end
  end
end

-- Stay near the boss, jumping and throwing the star.
PICK_INPUT = function(f)
  if phase ~= "fight" then
    return {start = (r(0x90) == 0 or r(0x90) >= 0xD0 or on_map()) and f % 60 < 5}
  end
  local t = f - t0
  local beat = t % 200
  return {right = beat < 90, left = beat >= 110 and beat < 170, a = f % 41 < 16, b = f % 97 < 50}
end
