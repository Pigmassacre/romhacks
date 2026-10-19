-- Coyote time: walk off a ledge and press A a few frames later.
-- In the hack a jump still works up to COYOTE_FRAMES frames after leaving
-- the floor. In the original game it never does.

local COYOTE = SYM.COYOTE_FRAMES
local function pit()
  -- Dig a pit to the right of the start (columns 7-9).
  local air = tile(7, 0x15)
  for x = 7, 9 do
    settile(x, 0x1A, air); settile(x, 0x1B, air)
  end
end

local function scenario(delay, expect)
  local left
  return {
    name = string.format("press A %d frames after leaving the floor", delay),
    len = 90,
    setup = function() pit(); left = nil end,
    input = function(f)
      local p = pad("R")
      if left and f == left + delay then p.a = true end
      return p
    end,
    frame = function(f)
      if not left and r(0x36E) < 0x80 then left = f; log(string.format("left the floor on frame %d at x=%02x.%02x", f, r(0xB8), r(0xAE))) end
      if left and f >= left and f <= left + delay + 2 then log(string.format("%3d %s", f, state())) end
      if left and f == left + delay then
        local jumped = s8(r(0xC2)) < -60
        if HACK then
          check(jumped == expect, string.format("jump=%s after %d frames (want %s)", tostring(jumped), delay, tostring(expect)))
        else
          check(not jumped, string.format("original: no jump after %d frames", delay))
        end
      end
      if f == 89 then check(left ~= nil, "walked off the ledge") end
    end,
  }
end

SCENARIOS = {
  scenario(1, true),
  scenario(3, true),
  scenario(COYOTE, true),
  scenario(COYOTE + 1, false),
  scenario(12, false),
}
run_scenarios()
