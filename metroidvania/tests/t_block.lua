-- Shots break Castlevania's breakable blocks: the hall's ($3F8, y $98)
-- breaks when a shot bursts on it, and its bit in $0146 is set. Samus is
-- flown beside it through the walls (the hack's debug flag, which shots
-- obey too, so it is off while she shoots).
local phase, t0 = "fly", 0
loadstate_raw("castle", function() w(0x70, 1) end)   -- the Long Beam
INPUT = function(f)
  if phase == "fly" then return pad("R") end
  if phase == "shoot" and f % 8 == 0 then return pad("B") end
  return {}
end
FRAME = function(f)
  w(0x5B, 0)
  for i = 4, 0x13 do if r(0x434 + i) == 0x01 or r(0x434 + i) == 0x03 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  local x = r(0x122) + 256 * r(0x123)
  if phase == "fly" then
    w(0x1C0, 0x80); w(0x124, 0x9E); w(0x10B, 0); w(0x109, 0)
    if x >= 0x3E0 then phase = "shoot"; t0 = f end
  end
  if phase == "shoot" then
    w(0x1C0, 0); w(0x124, 0x9E); w(0x10B, 0); w(0x109, 0); w(0x111, 0)   -- held there, shots hitting walls
    if (r(0x146) & 1) ~= 0 and f > t0 + 40 then
      check(true, "the block breaks")
      shot("broken"); done()
    end
    if f > t0 + 300 then check(false, "the block breaks"); shot("unbroken"); done() end
  end
  if f > 3000 then check(false, "got there"); done() end
end
