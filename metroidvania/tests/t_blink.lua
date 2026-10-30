-- While enemies can't touch her (Castlevania's $5B: after a hit, on the
-- stairs, and the invisibility potion's $B4) Samus blinks, as Simon does.
-- Without the blink, the potion showed nothing at all. (Sprite RAM shows
-- the frame before. Samus's tiles are Simon's: candles use $50.)
local function samus_sprites()
  local n = 0
  for i = 17, 63 do
    local y = emu.read(i * 4, emu.memType.nesSpriteRam)
    local t = emu.read(i * 4 + 1, emu.memType.nesSpriteRam)
    if y < 0xEF and t % 2 == 0 and (t < 0x40 or (t >= 0x46 and t < 0x50) or (t >= 0x52 and t < 0x60) or (t >= 0x6A and t < 0x70)) then n = n + 1 end
  end
  return n
end
local shown, hidden = 0, 0
loadstate_raw("castle")
FRAME = function(f)
  for i = 4, 0x13 do if r(0x434 + i) == 0x01 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  if f == 10 then
    check(samus_sprites() > 0, "drawn")
    w(0x5B, 0xB4)                                 -- the potion
  end
  if f > 12 and f <= 72 then
    if samus_sprites() > 0 then shown = shown + 1 else hidden = hidden + 1 end
  end
  if f == 73 then
    check(shown >= 28 and hidden >= 28, string.format("with the potion she blinks (%d frames shown, %d hidden)", shown, hidden))
    check(r(0x5B) > 0, "and is still invincible")
    done()
  end
end
