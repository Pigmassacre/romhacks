-- Castlevania's crushers (stage 6's lower floor) kill Simon outright, unless
-- he is jumping (action 1): then they only hurt him ($8282). Samus in the air
-- counts as jumping (the hack once left Simon's action at 0, and they killed
-- her mid-jump). She is flown under the middle one ($1A0) and held in the
-- air against its spikes.
local phase, t0, hurt = "warp", 0, false
loadstate_raw("castle", function() w(0x28, 6); w(0x29, 6); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9) end)
INPUT = function(f) return phase == "fly" and pad("L") or {} end
FRAME = function(f)
  if phase ~= "warp" then w(0x118, 9) end
  for i = 4, 0x13 do if r(0x434 + i) ~= 0 and r(0x434 + i) < 0x20 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  local x = r(0x122) + 256 * r(0x123)
  if phase == "warp" and f > 60 and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 6 and (r(0x126) & 1) == 1 then phase = "fly"; t0 = f end
  if phase == "fly" then
    w(0x1C0, 0x80); w(0x124, 0xA0); w(0x10B, 0); w(0x109, 0); w(0x5B, 0x40)
    if x <= 0x1AA then w(0x1C0, 0); phase = "air"; t0 = f end
  end
  if phase == "air" then
    -- in the air, against the spikes: the crusher reaches y $70 + 4 + 8 per step
    local bottom = 0x70 + 4 + (r(0x156) & 0x0F) * 8
    w(0x122, 0xAA); w(0x123, 0x01); w(0x124, bottom + 1); w(0x109, 0)
    if f == t0 + 2 then w(0x5B, 0) end
    if r(0x46C) == 5 or r(0x107) ~= 0 or r(0x113) ~= 0 then hurt = true end
    if f == t0 + 30 then
      check(r(0x46C) ~= 8, string.format("in the air, the crusher doesn't kill her (action %d)", r(0x46C)))
      check(hurt, "it hurts her")
      done()
    end
  end
  if f > 3000 then check(false, "got there (" .. phase .. ")"); done() end
end
