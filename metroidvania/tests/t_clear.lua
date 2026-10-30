-- Clearing a stage fills Samus's energy: the orb ($E83A) sets Simon's health
-- to full and starts the stage's end, as this does by hand, with little energy
-- left.
loadstate_raw("castle", function() w(0x28, 3); w(0x118, 1); w(0x117, 0x50); w(0x45, 0x40); w(0x18, 0x0C); w(0x19, 0) end)
FRAME = function(f)
  if r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 4 and (r(0x126) & 1) == 1 then
    shot("next")
    check(r(0x118) == 9 and r(0x117) == 0x90, string.format("energy full in the next stage (%x%02x)", r(0x118), r(0x117)))
    done()
  end
  if f > 3000 then check(false, "the next stage came"); done() end
end
