-- Missiles: Select arms them, and each one fired costs a heart. Missiles only
-- use the first of Samus's three shots, as in Metroid. Firing with all three
-- shots busy once took a fourth, past the end, which wrote over the first:
-- if that one was exploding, it went on exploding for good, and missiles
-- never fired again. Here three long beams go up, the first is made to
-- explode (as hitting something does), and B is pressed again; then
-- missiles are armed and fired.
local phase, t0, h0 = "fire", 0, 0
loadstate_raw("castle", function() w(0x70, 1) end)   -- the first whip upgrade: Long Beam
INPUT = function(f)
  if phase == "fire" then return {up = true, b = f % 4 == 0} end
  if phase == "fourth" and f == t0 + 3 then return pad("U B") end
  if phase == "fourth" then return pad("U") end
  if phase == "arm" and f == t0 + 2 then return pad("E") end
  if (phase == "missile" or phase == "missile2") and f == t0 + 2 then return pad("B") end
  return {}
end
local function shots() return string.format("%02x %02x %02x", r(0x7CF), r(0x7D0), r(0x7D1)) end
FRAME = function(f)
  if phase == "fire" and r(0x7CF) ~= 0 and r(0x7D0) ~= 0 and r(0x7D1) ~= 0 then
    -- the first explodes: UpdateBullet_Explode
    w(0x7CF, 0x04); w(0x7D5, 0x1D); w(0x7D2, 0x1D); w(0x7D8, 0x10)   -- (slowly)
    phase = "fourth"; t0 = f
  end
  if phase == "fourth" and f == t0 + 90 then
    check(r(0x7CF) == 0 and r(0x7D0) == 0 and r(0x7D1) == 0,
      "firing with all three shots busy fires nothing, and they all end (" .. shots() .. ")")
    phase = "arm"; t0 = f; h0 = r(0x71)
  end
  if phase == "arm" and f == t0 + 10 then
    check(r(0x11B) == 1, "Select arms missiles")
    phase = "missile"; t0 = f
  end
  if phase == "missile" and f == t0 + 4 then
    check(r(0x7CF) == 0x0B, string.format("B fires a missile (shot status %02x)", r(0x7CF)))
    check(r(0x71) == h0 - 1, string.format("it costs a heart (%d, then %d)", h0, r(0x71)))
    phase = "wait"
  end
  if phase == "wait" and r(0x7CF) == 0 then phase = "missile2"; t0 = f end
  if phase == "missile2" and f == t0 + 4 then
    check(r(0x71) == h0 - 2, "and the next one, another")
    done()
  end
  if f > 1500 then check(false, "got through (" .. phase .. ", shots " .. shots() .. ")"); done() end
end
