-- After the mummies, Castlevania drops Simon down a shaft into stage 10: he
-- comes in at the top of the screen and falls to the ground. The hack takes
-- everything above the playfield (y < $30) to be solid, so that Samus can't
-- jump out of it; she came in inside it, stuck, and died as soon as she
-- moved. She falls in now, lands, and walks off. Stage 9 is cleared by hand.
local phase, t0, died = "wait", 0, false
loadstate_raw("castle", function() w(0x28, 9); w(0x18, 0x0C); w(0x19, 0) end)
INPUT = function(f) return (phase == "in" and f > t0 + 100) and pad("R") or {} end
FRAME = function(f)
  if phase == "wait" and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 10 then phase = "in"; t0 = f end
  if phase == "in" then
    if r(0x46C) == 8 then died = true end
    if f == t0 + 100 then
      check(not died, "she lives")
      check(r(0x124) > 0x40 and r(0x10B) == 0, string.format("she fell in and landed (y %02x)", r(0x124)))
      X0 = r(0x122) + 256 * r(0x123)
    end
    if f == t0 + 160 then
      check(r(0x122) + 256 * r(0x123) > X0 + 0x20, "and walks off")
      done()
    end
  end
  if f > 3000 then check(false, "into stage 10"); done() end
end
