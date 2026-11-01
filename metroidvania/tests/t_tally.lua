-- A stage's end counts the time down: each digit on the HUD keeps up, not just the
-- last one, which changes every time (the others once never got their turn).
local seen = {{}, {}, {}}
local phase = "wait"
loadstate_raw("castle", function() w(0x28, 3); w(0x43, 0x05); w(0x42, 0x99); w(0x18, 0x0C); w(0x19, 0) end)
FRAME = function(f)
  if r(0x18) == 0x0C and r(0x19) == 2 then
    phase = "count"
    -- the last 3 digit columns hold the boss over the time
    for c = 1, 3 do seen[c][r(0x1C1 + c + 2) & 0x0F] = true end
  end
  if phase == "count" and r(0x19) >= 3 then
    for c = 1, 3 do
      local n = 0
      for _ in pairs(seen[c]) do n = n + 1 end
      check(n >= 3, string.format("time's column %d showed %d different digits", c, n))
    end
    done()
  end
  if f > 3000 then check(false, "the count came"); done() end
end
