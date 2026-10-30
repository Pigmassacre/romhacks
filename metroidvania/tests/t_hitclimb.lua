-- A hit sets $054C for Simon's knockback ($96DC), and Samus doesn't run his
-- handler, which counts it down. Left set, the climb from stage 10 to 11 goes
-- wrong: she came in at floor 255 and fell through the ground. She is hit by
-- hand here, as that code does, on the way to stage 10's end.
local phase = "warp"
loadstate_raw("castle", function()
  w(0x28, 0x0A); w(0x29, 0x0A); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
local function x() return r(0x122) + 256 * r(0x123) end
INPUT = function(f) return (phase == "fly" or phase == "walk") and pad("R") or {} end
FRAME = function(f)
  w(0x118, 9); w(0x5B, 0x40); w(0x43, 3)
  if phase == "warp" and f > 120 and r(0x18) == 5 and r(0x19) == 6 then phase = "fly" end
  if phase == "fly" then
    w(0x1C0, 0x80); w(0x124, 0x70); w(0x10B, 0); w(0x109, 0)
    if x() >= 0x5C8 then w(0x1C0, 0); w(0x54C, 4); phase = "walk" end
    if f > 4000 then check(false, "got there"); done() end
  end
  if phase == "walk" and r(0x28) == 11 then phase = "next" end
  if phase == "next" and r(0x18) == 5 and r(0x19) == 6 and (r(0x126) & 1) == 1 then
    check(r(0x46) == 0, string.format("on stage 11's only floor (%d)", r(0x46)))
    check(r(0x124) == 0xB1, string.format("on the ground (y %02x)", r(0x124)))
    done()
  end
  if f > 6000 then check(false, "stage 11 came (" .. phase .. ")"); done() end
end
