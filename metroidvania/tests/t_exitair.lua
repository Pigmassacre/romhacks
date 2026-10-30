-- Reaching a stage's exit in mid-jump: only Simon's walking handler looks for
-- exits, so Castlevania's way out never saw him in the air, as it sees her.
local phase = "warp"
loadstate_raw("castle", function()
  w(0x28, 0x0A); w(0x29, 0x0A); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
local function x() return r(0x122) + 256 * r(0x123) end
INPUT = function(f) return phase == "fly" and pad("R") or {} end
FRAME = function(f)
  w(0x118, 9); w(0x5B, 0x40); w(0x43, 3)
  if phase == "warp" and f > 120 and r(0x18) == 5 and r(0x19) == 6 then phase = "fly" end
  if phase == "fly" then
    w(0x1C0, 0x80); w(0x124, 0x60); w(0x10B, 0); w(0x109, 0)
    if x() >= 0x5E0 and r(0x2F) == 5 then
      -- high above the block, falling: through the exit's window in the air
      w(0x122, 0xDC); w(0x1C0, 0); w(0x10B, 0x18); phase = "fall"
    end
    if f > 4000 then check(false, "got there"); done() end
  end
  if phase == "fall" and r(0x28) == 11 then
    check(r(0x10B) ~= 0, "the exit came in mid-air")
    phase = "next"
  end
  if phase == "next" and r(0x18) == 5 and r(0x19) == 6 and (r(0x126) & 1) == 1 then
    check(r(0x46) == 0, string.format("on stage 11's only floor (%d)", r(0x46)))
    check(r(0x124) == 0xB1, string.format("on the ground (y %02x)", r(0x124)))
    done()
  end
  if f > 6000 then check(false, string.format("stage 11 came (%s, x %04x y %02x stage %d)", phase, x(), r(0x124), r(0x28))); done() end
end
