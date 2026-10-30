-- Medusa (stage 6) waits at the left end of the stage's upper floor: the
-- screen locks for her when it scrolls left onto her screen. Castlevania
-- checks every frame, whichever way the screen goes; the hack once checked
-- only when Samus scrolled right, so the screen never locked for Medusa,
-- Death or Dracula. Samus climbs the stairs to the upper floor, then flies
-- left (through the walls, the hack's debug flag).
local phase, t0 = "warp", 0
local function x() return r(0x122) + 256 * r(0x123) end
loadstate_raw("castle", function()
  w(0x28, 6); w(0x29, 6); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
INPUT = function(f)
  if phase == "up" and f > t0 + 2 then return pad("U") end
  if phase == "fly" then return pad("L") end
  return {}
end
FRAME = function(f)
  w(0x118, 9); w(0x5B, 0x40)
  if phase == "warp" and f > 60 and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 6 and (r(0x126) & 1) == 1 then
    -- the foot of the stairs up ($290, y $41)
    w(0x122, 0x90); w(0x123, 2); w(0x124, 0x3D); phase = "drop"; t0 = f
  end
  if phase == "drop" and f == t0 + 40 then phase = "up"; t0 = f end
  if phase == "up" and f > t0 + 20 and r(0x46C) == 0 then
    check(r(0x46) == 1, "up the stairs to the upper floor")
    phase = "fly"; t0 = f
  end
  if phase == "fly" then
    w(0x1C0, 0x80); w(0x124, 0x90); w(0x10B, 0); w(0x109, 0)
    if r(0x48) ~= 0 or f > t0 + 1500 then
      w(0x1C0, 0)
      check(r(0x48) == 1 and r(0x2F) == 0 and r(0x2E) == 0, string.format("the screen locks at Medusa's screen (lock %d, scroll %02x%02x)", r(0x48), r(0x2F), r(0x2E)))
      done()
    end
  end
  if f > 4000 then check(false, "got there (" .. phase .. ")"); done() end
end
