-- Running out of time kills Simon. Castlevania checks the time in Simon's
-- handlers ($9A1D), which Samus's replace: she once lived on at 0 until she
-- took the stairs, and died there.
local t0 = nil
loadstate_raw("castle", function() w(0x42, 0x02); w(0x43, 0x00) end)
FRAME = function(f)
  for i = 4, 0x13 do if r(0x434 + i) == 0x01 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  if not t0 and r(0x42) == 0 and r(0x43) == 0 then t0 = f end
  if t0 and f == t0 + 10 then
    check(r(0x46C) == 8, string.format("out of time, she dies (action %d)", r(0x46C)))
    check(r(0x100) == 8, "and explodes")
    done()
  end
  if f > 600 then check(false, string.format("the time ran out (%02x%02x)", r(0x43), r(0x42))); done() end
end
