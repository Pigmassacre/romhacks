-- Samus's shots hold Castlevania's subweapon slots ($14-$16) as daggers with
-- no sprite of their own. When one hits, Castlevania turns it into a spark,
-- whose pose animation must not carry on into the next shot in that slot
-- (it drew Castlevania's hit flame, like a ghost, on every other shot).
-- Shooting along the hall, through zombies and candles, a dagger never has
-- a pose, and shots do hit things.
local posed, hits, lastai = 0, 0, {}
loadstate_raw("castle")
INPUT = function(f)
  local t = {}
  if f % 12 == 0 then t.b = true end
  if f % 200 < 120 then t.right = true end
  return t
end
FRAME = function(f)
  for x = 0x14, 0x16 do
    local ai = r(0x434 + x)
    if ai == 0x17 and r(0x31C + x) ~= 0 then
      posed = posed + 1
      if posed < 4 then log(string.format("frame %d: slot %02x has pose %02x", f, x, r(0x31C + x))) end
    end
    if lastai[x] == 0x17 and ai == 0x32 then hits = hits + 1 end
    lastai[x] = ai
  end
  if f == 900 then
    check(hits >= 3, string.format("shots hit things (%d hits)", hits))
    check(posed == 0, string.format("a shot's dagger never has a sprite (%d frames did)", posed))
    done()
  end
end
