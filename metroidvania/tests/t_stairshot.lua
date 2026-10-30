-- On the stairs Castlevania moves Samus, and B would start Simon's whip,
-- drawn with Samus's tiles (her heads stretched out in front of her). B
-- fires her beam there instead, and shots already in flight keep moving
-- (they once hung in the air until she was off the stairs).
local phase, t0, whip, x0, moved, fired = "back", 0, 0, 0, false, false
loadstate_raw("stairs1", function() w(0x70, 1) end)   -- the Long Beam: the short one is gone before she is on the stairs
INPUT = function(f)
  if phase == "back" then return pad("L") end
  if phase == "shoot" and f == t0 + 1 then return pad("B") end
  if phase == "shoot" and f > t0 + 2 then return (f % 2 == 0) and pad("U") or {} end
  if phase == "fire" and (f == t0 + 2 or f == t0 + 20 or f == t0 + 40) then return pad("B") end
  if phase == "fire" then return (f % 2 == 0) and pad("U") or {} end
  return {}
end
FRAME = function(f)
  for i = 4, 0x13 do if r(0x434 + i) == 0x01 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  local x = r(0x122) + 256 * r(0x123)
  if r(0x31D) ~= 0 then whip = whip + 1 end      -- the whip (slot 1) has a pose
  if phase == "back" and x <= 0x508 then phase = "shoot"; t0 = f end
  -- a shot fired at the stairs' foot, then up them
  if phase == "shoot" and f == t0 + 3 then x0 = r(0x7E4) + 256 * r(0x7E7) end
  if phase == "shoot" and r(0x46C) == 4 and r(0x7CF) ~= 0 and r(0x7E4) + 256 * r(0x7E7) ~= x0 then moved = true end
  if phase == "shoot" and f == t0 + 40 then
    check(moved, "a shot in flight keeps moving while she climbs")
    phase = "fire"; t0 = f
  end
  if phase == "fire" and r(0x46C) == 4 and r(0x7CF) ~= 0 and f > t0 + 2 then fired = true end
  if phase == "fire" and f == t0 + 60 then
    check(r(0x46C) == 4, "still on the stairs")
    check(fired, "B on the stairs fires her beam")
    check(whip == 0, string.format("and no whip (%d frames had one)", whip))
    done()
  end
  if f > 2000 then check(false, "got to the stairs (" .. phase .. ")"); done() end
end
