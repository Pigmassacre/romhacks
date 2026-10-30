-- Shots stop being Samus's when Castlevania takes over for good: dying, a
-- door, a stage's end. Nothing moves them then, and they once hung in the
-- air, drawn, through the whole death.
local phase, t0 = "shoot", 0
loadstate_raw("castle", function() w(0x70, 1) end)   -- the Long Beam
INPUT = function(f) return (f == 4) and pad("B") or {} end
FRAME = function(f)
  for i = 4, 0x13 do if r(0x434 + i) == 0x01 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  if f == 8 then
    check(r(0x7CF) ~= 0, "a shot in flight")
    w(0x118, 0); w(0x117, 0x10); w(0x45, 0)       -- and she dies
  end
  if f == 40 then
    check(r(0x46C) == 8, "dying")
    check(r(0x7CF) == 0 and r(0x7D0) == 0 and r(0x7D1) == 0, string.format("no shots left (%02x %02x %02x)", r(0x7CF), r(0x7D0), r(0x7D1)))
    done()
  end
end
