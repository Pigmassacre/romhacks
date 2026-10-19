-- Run with --rom on the original game: nothing may write the hack's RAM
-- ($0470-$048C). Goes through every stage start, deaths and a game over.
-- With the hack, only code in the hack bank ($A000-$BFFF) may write it.
local writes = 0
emu.addMemoryCallback(function(a, v)
  local pc = emu.getState()["cpu.pc"]
  if HACK and pc >= 0xA000 and pc < 0xC000 then return end
  if pc >= 0xE078 and pc <= 0xE07B and v == 0 then return end   -- the reset code clearing RAM
  writes = writes + 1
  if writes <= 10 then log(string.format("write %04x=%02x from pc=%04x", a, v, pc)) end
end, emu.callbackType.write, 0x0470, 0x048C)

local stage, phase, t0 = 0, "play", 0
INPUT = function(f)
  if phase == "gameover" then return {start = (f % 120) < 4} end
  -- wander around and use the star
  local p = math.floor(f / 50) % 4
  return {right = p < 3, left = p == 3, a = (f % 37) < 15, b = (f % 90) < 45}
end
FRAME = function(f)
  if phase == "play" then
    if f == t0 + 300 then shot("stage" .. stage) end
    if f > t0 + 400 then
      stage = stage + 1
      if stage > 6 then phase = "gameover"; w(0x104, 0); w(0x346, 0); t0 = f return end
      w(0x1B, stage); w(0x1C, 0); w(0x346, 0); w(0x104, 9)
      t0 = f
    end
  elseif phase == "gameover" then
    -- out of lives: game over, title, and back in again
    if (f - t0) % 500 == 250 then shot(string.format("over%04d", f - t0)) end
    if f > t0 + 3000 then
      check(writes == 0, string.format("%d writes to the hack's RAM", writes))
      done()
    end
  end
end
