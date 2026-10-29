-- Where the screen can't scroll, left of its middle Samus walks on the screen
-- instead. That once failed going left (her screen x was lost), so she
-- stopped at x $70: at the start of stage 4 she couldn't get back along the
-- middle floor to the stairs' foot, and in a boss fight the left half of
-- the screen was out of reach.
local phase, t0 = "warp", 0
local function x() return r(0x122) + 256 * r(0x123) end
loadstate_raw("castle", function()
  w(0x28, 4); w(0x29, 4); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
INPUT = function(f)
  if phase == "left" then return pad("L") end
  if phase == "up" and f == t0 + 2 then return pad("U") end
  if phase == "up" and f > t0 + 2 then return pad("U") end
  if phase == "lockleft" then return pad("L") end
  return {}
end
FRAME = function(f)
  w(0x118, 9); w(0x5B, 0x40)
  for i = 4, 0x13 do if r(0x434 + i) ~= 0x28 then w(0x434 + i, 0); w(0x31C + i, 0) end end   -- no enemies
  if phase == "warp" and f > 120 and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 4 then
    -- onto the middle floor, right of the stairs, the screen at the stage's start
    w(0x122, 0x80); w(0x123, 1); w(0x124, 0x50); phase = "drop"; t0 = f
  end
  if phase == "drop" and f == t0 + 30 then phase = "left"; t0 = f end
  if phase == "left" and x() <= 0x150 then
    check(true, string.format("along the middle floor to the stairs' foot (scroll %02x%02x)", r(0x2F), r(0x2E)))
    phase = "stop"; t0 = f
  end
  if phase == "left" and f == t0 + 60 then check(false, string.format("along the middle floor to the stairs' foot (stopped at x %04x)", x())); done() end
  if phase == "stop" and f == t0 + 10 then phase = "up"; t0 = f end
  if phase == "up" and f == t0 + 40 then
    check(r(0x46C) == 4, string.format("up takes her up the stairs (action %d)", r(0x46C)))
    -- now as in a boss fight: the screen locked, Samus right of its middle
    w(0x46C, 0); w(0x48, 1); w(0x122, 0xA0); w(0x123, 1); w(0x124, 0x50)
    phase = "lockdrop"; t0 = f
  end
  if phase == "lockdrop" and f == t0 + 30 then phase = "lockleft"; t0 = f end
  if phase == "lockleft" and f == t0 + 60 then
    local sx = r(0x38C)
    check(sx < 0x40 and r(0x2E) == 0 and r(0x2F) == 1, string.format("with the screen locked she walks left of its middle (screen x %02x)", sx))
    done()
  end
  if f > 3000 then check(false, "got there (" .. phase .. ")"); done() end
end
