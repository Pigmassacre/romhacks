-- The title screen is Castlevania's: its bat (object slot 0, which in play
-- is Simon) is drawn where it flies, and it lands on the castle, which ends
-- its path (the hack's code once covered the $FF that ends it at $BA3B: the
-- bat flew off over the screen and the demo never came).
local landed = false
FRAME = function(f)
  if f == 100 then
    shot("title")
    local bx, by, bat = r(0x38C), r(0x354), false
    for i = 17, 63 do
      local y, x = emu.read(i * 4, emu.memType.nesSpriteRam), emu.read(i * 4 + 3, emu.memType.nesSpriteRam)
      if y < 0xEF and math.abs(x - bx) < 24 and math.abs(y - by) < 24 then bat = true end
    end
    check(bat, string.format("the bat drawn where it is (%02x, %02x)", bx, by))
    check(r(0x18) == 1, "on the title")
  end
  if r(0x18) == 1 and r(0x19) == 1 then landed = true end
  if f == 300 then
    check(landed, "the bat lands on the castle")
    done()
  end
end
