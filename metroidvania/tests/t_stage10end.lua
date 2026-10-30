-- Stage 10's exit is on the last of three staggered blocks, which Samus is too
-- tall to climb. Walking to the end of the block before it, she goes on to
-- stage 11.
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
    w(0x1C0, 0x80); w(0x124, 0x80); w(0x10B, 0); w(0x109, 0)   -- at the block's height: only its end counts
    check(r(0x28) == 10 or x() >= 0x5C8, "not elsewhere in the stage")
    if r(0x28) ~= 10 then done() end
    if x() >= 0x5C8 then w(0x124, 0x70); w(0x1C0, 0); phase = "walk"; check(r(0x2F) == 5, "at the stage's end") end
    if f > 4000 then check(false, "got there"); done() end
  end
  if phase == "walk" and r(0x28) == 11 then
    check(true, string.format("on to stage 11 (mode %02x/%02x)", r(0x18), r(0x19)))
    done()
  end
  if f > 6000 then check(false, string.format("stage 11 came (x %04x y %02x)", x(), r(0x124))); done() end
end
