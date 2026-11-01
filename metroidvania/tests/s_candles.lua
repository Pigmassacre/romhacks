-- Not a test: the bot plays the game, and this logs what each candle holds and what
-- drops: stage, floor, x in the stage, the object's AI and type.
dofile(REPO .. "/tests/s_play.lua")
local playFrame = FRAME
local seen = {}
FRAME = function(f)
  playFrame(f)
  for s = 4, 0x13 do
    local ai, ty = r(0x434 + s), r(0x584 + s)
    if ai == 0x28 or (ai == 0x2F and ty ~= 0 and ty ~= 6) then
      local lx = r(0x2E) + 256 * r(0x2F) + r(0x38C + s)
      local key = string.format("%d %d %d %02x %02x", r(0x28), r(0x46), lx // 16, ai, ty)
      if not seen[key] then
        seen[key] = true
        log(string.format("OBJ stage %d floor %d x %d y %d ai %02x type %02x pose %02x", r(0x28), r(0x46), lx, r(0x354 + s), ai, ty, r(0x31C + s)))
      end
    end
  end
end
