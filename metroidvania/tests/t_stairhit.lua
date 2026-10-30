-- Hit on the stairs, Castlevania only stuns Simon and takes the hit off his
-- health; the hack turns that into Samus's energy as it happens. It once
-- waited until she was off the stairs: until then the hits added up in
-- Simon's health, and three hits in the later stages took it below 0, which
-- read as a refill. Samus climbs the hall's last stairs and Castlevania's
-- hits are made as $E754 makes them (12 off Simon's health): three take 54
-- energy, and she stays on the stairs. Then, with 10 energy, a hit of 16
-- kills her, and she comes back.
local phase, t0, hits = "wait", 0, 0
local function energy() return (r(0x118) & 0x0F) * 10 + (r(0x117) >> 4) end
loadstate_raw("stairs1")
INPUT = function(f)
  if phase == "back" then return pad("L") end
  if phase == "up" or phase == "hit" or phase == "kill" then return (f % 2 == 0) and pad("U") or {} end
  return {}
end
FRAME = function(f)
  if phase ~= "kill" then w(0x5B, 0x40) end      -- no zombies' hits
  local x = r(0x122) + 256 * r(0x123)
  if phase == "wait" and f == 10 then phase = "back" end
  if phase == "back" and x <= 0x510 then phase = "up" end
  if phase == "up" and r(0x46C) == 4 then phase = "hit"; t0 = f; w(0x118, 9); w(0x117, 0x90) end
  if phase == "hit" and (f - t0) % 20 == 5 and hits < 3 then
    hits = hits + 1; w(0x45, r(0x45) - 12)
  end
  if phase == "hit" and f == t0 + 70 then
    check(r(0x46C) == 4, string.format("still on the stairs (action %d)", r(0x46C)))
    check(energy() == 45, string.format("three hits of 12 took 54 energy (%d left)", energy()))
    w(0x118, 1); w(0x117, 0x00); w(0x45, r(0x45) - 16)
    phase = "kill"; t0 = f
  end
  if phase == "kill" and f == t0 + 30 then
    check(r(0x46C) == 8, string.format("with 10 energy, a hit of 16 kills her (action %d)", r(0x46C)))
    phase = "dead"
  end
  if phase == "dead" and r(0x18) == 5 and r(0x19) == 6 and (r(0x126) & 1) == 1 and r(0x46C) == 0 then
    check(energy() == 99, string.format("back with full energy (%d)", energy()))
    done()
  end
  if f > 3000 then check(false, "got onto the stairs (" .. phase .. ")"); done() end
end
