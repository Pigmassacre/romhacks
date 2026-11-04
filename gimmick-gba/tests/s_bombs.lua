-- The first stage's room of bombs hanging from the roof, for tools/record.py --bombs:
-- Yumetaro stands under them with the fireball item and charges it, again and again,
-- which slowed the GBA down. It warps to the stage's second checkpoint, and goes before
-- s_record.lua.
local phase, t0 = "boot", 0
local function on_map() return r(0x40) == 0x1C or r(0x40) == 0x1B end
local function in_stage() return r(0x90) == 1 and not on_map() end

ON_NMI = function(f)
  if phase == "boot" then
    if r(0x90) == 1 and f > 600 then
      poke(0x1B, 0); poke(0x1C, 1); poke(0x346, 0); poke(0x104, 9)
      phase = "dying"; t0 = f
    end
  elseif phase == "dying" then
    if in_stage() and f > t0 + 60 then
      phase = "charge"; t0 = f
    end
  else
    -- Health at its most ($2B), not above it: see s_boss.lua.
    if r(0x346) < r(0x2B) then poke(0x346, r(0x2B)) end
    if r(0x36) == 0 then poke(0x36, 2) end  -- the fireball, again once it is used
    if (f - t0) % 150 == 0 then
      local h = io.open(OUT .. "shot_" .. (f - t0) .. ".png", "wb")
      h:write(emu.takeScreenshot()); h:close()
    end
  end
end

-- Up and B charge the item, held for a while, then let go to throw it.
PICK_INPUT = function(f)
  if phase ~= "charge" then
    return {start = (r(0x90) == 0 or r(0x90) >= 0xD0 or on_map()) and f % 60 < 5}
  end
  local beat = (f - t0) % 240
  return {up = beat >= 20 and beat < 200, b = beat >= 20 and beat < 200}
end
