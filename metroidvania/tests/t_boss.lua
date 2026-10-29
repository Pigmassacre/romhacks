-- The Phantom Bat (stage 3): the screen locks for it when Samus scrolls to
-- its screen (Castlevania checks that in Simon's walking code; the hack at
-- every pixel Samus scrolls), and her shots wear its health ($01A9) down
-- to nothing. She gets there through the walls (the hack's debug flag),
-- flying at y $70. In the fight no enemies come (the hall's zombies once
-- did: Samus scrolled past the edge where Castlevania replaces their
-- generator).
local phase, t0, hp0, zombies = "warp", 0, 0, 0
loadstate_raw("castle", function()
  w(0x28, 3); w(0x29, 3); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
INPUT = function(f)
  if phase == "fly" then return pad("R") end
  if phase == "fight" then
    local t = {}
    if f % 6 == 0 then t.b = true end
    if (f // 60) % 2 == 0 then t.up = true end
    if f % 50 < 20 then t.a = true end
    if (f // 120) % 2 == 0 then t.right = (f % 10 < 3) else t.left = (f % 10 < 3) end
    return t
  end
  return {}
end
FRAME = function(f)
  w(0x118, 9)                                     -- energy to spare
  if phase == "warp" and f > 120 and r(0x18) == 5 and r(0x19) == 6 then phase = "fly" end
  if phase == "fly" then
    w(0x1C0, 0x80); w(0x124, 0x70); w(0x10B, 0); w(0x109, 0)
    if r(0x48) ~= 0 then
      w(0x1C0, 0)
      check(r(0x2F) == 2 and r(0x2E) == 0, string.format("locked at the boss's screen (scroll %02x%02x)", r(0x2F), r(0x2E)))
      phase = "fight"; t0 = f; hp0 = r(0x1A9)
    end
    if r(0x28) ~= 3 then check(false, "the screen locks for the boss"); done() end
  end
  if phase == "fight" then
    for i = 4, 0x13 do
      if r(0x434 + i) == 0x01 then zombies = zombies + 1 end
    end
    if r(0x1A9) == 0 then
      check(hp0 == 0x40, "the boss started with full health")
      check(zombies == 0, string.format("no zombies in the fight (%d slot-frames had one)", zombies))
      check(true, string.format("the boss is beaten, in %d frames", f - t0))
      shot("beaten"); done()
    end
    if f > t0 + 3000 then check(false, string.format("the boss is beaten (health %02x)", r(0x1A9))); done() end
  end
  if f > 6000 then check(false, "got to the boss (" .. phase .. ")"); done() end
end
