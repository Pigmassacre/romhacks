-- The title screen is Castlevania's: its bat (object slot 0, which in play is
-- Simon) is still drawn, and the status bar still shows on the title.
FRAME = function(f)
  if f == 200 then
    shot("title")
    local bat = false
    for i = 17, 63 do
      local t = emu.read(i * 4 + 1, emu.memType.nesSpriteRam)
      if emu.read(i * 4, emu.memType.nesSpriteRam) < 0xEF then bat = true end
    end
    check(bat, "title sprites drawn")
    check(r(0x18) == 1, "on the title")
    done()
  end
end
