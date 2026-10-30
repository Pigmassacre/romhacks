-- The holes stairs make in a floor are 8 pixels wide, as wide as Samus's cells.
-- Stage 7's first stairs come up through one: walking off the top, at x $44,
-- she once fell through, to her death.
local phase, t0, died, dir = "towarp", 0, false, nil
local maxy = 0
local function x() return r(0x122) + 256 * r(0x123) end
loadstate_raw("castle", function() end)
INPUT = function(f)
  if phase == "stairfly" then return dir end
  if phase == "press" and f > t0 + 2 then return pad("U") end
  if phase == "off" then return f % 8 < 3 and pad("R") or {} end       -- slowly over it
  return {}
end
FRAME = function(f)
  if phase ~= "towarp" and phase ~= "warp" then w(0x118, 9); w(0x5B, 0x40) end
  if phase == "towarp" and r(0x18) == 5 then
    w(0x28, 7); w(0x29, 7); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9); phase = "warp"
  end
  if r(0x18) == 6 then died = true end
  if phase == "warp" and not died and r(0x18) == 5 then w(0x5B, 0); w(0x113, 0); w(0x45, 0) end
  if phase == "warp" and died and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 7 and (r(0x126) & 1) == 1 then phase = "stairfly" end
  if phase == "stairfly" then
    local tx = 0x9F
    w(0x1C0, 0x80); w(0x124, 0x71 - 0x10); w(0x10B, 0); w(0x109, 0)
    local d = tx - x()
    if math.abs(d) <= 2 then
      w(0x122, tx % 256); w(0x123, 0); w(0x124, 0x71 - 4); w(0x1C0, 0); phase = "land"; t0 = f
    else dir = d > 0 and pad("R") or pad("L") end
  end
  if phase == "land" and f == t0 + 40 then phase = "press"; t0 = f end
  if phase == "press" and f > t0 + 20 and r(0x46C) ~= 4 and r(0x46C) ~= 6 then
    check(r(0x46) == 1, string.format("up the stairs to the upper floor (x %02x y %02x)", r(0x122), r(0x124)))
    phase = "off"; t0 = f
  end
  if phase == "off" then
    maxy = math.max(maxy, r(0x124))
    if f == t0 + 90 then
      check(r(0x122) > 0x44, string.format("she walked off it (x %02x)", r(0x122)))
      check(maxy <= 0xB2, string.format("over the hole, not into it (y to %02x)", maxy))
      done()
    end
    if r(0x18) ~= 5 then check(false, "she died"); done() end
  end
  if f > 3000 then check(false, "got there (" .. phase .. ")"); done() end
end
