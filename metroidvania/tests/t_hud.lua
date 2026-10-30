-- Metroid's HUD: EN, the energy and the missile count (hearts) as sprites
-- 7-16, its digits drawn into the pattern table; Castlevania's status bar
-- blank, and sprite palette 2 in Metroid's HUD colours above the split.
loadstate_raw("castle", function() w(0x118, 0x05); w(0x117, 0x70); w(0x71, 42) end)
FRAME = function(f)
  -- sprites 1-8 are Castlevania's own (the moving platforms, Dracula's
  -- head): the HUD leaves them alone
  if f == 20 then w(0x20C, 0x80) end
  if f == 40 then
    check(r(0x20C) == 0x80, "sprite 3 left alone")
    shot("hud")
    -- sprites 7-11: the columns, at Metroid's x positions
    local xs = {0x18, 0x20, 0x28, 0x30, 0x38}
    for i = 1, 5 do
      check(emu.read((6 + i) * 4 + 3, emu.memType.nesSpriteRam) == xs[i], string.format("HUD column %d at x=%02x", i, xs[i]))
    end
    -- no line of it has more sprites than a line can show
    local most = 0
    for line = 0, 60 do
      local n = 0
      for i = 7, 16 do
        local y = emu.read(i * 4, emu.memType.nesSpriteRam)
        if line > y and line <= y + 16 then n = n + 1 end
      end
      most = math.max(most, n)
    end
    check(most <= 8, string.format("at most 8 sprites on a line (%d)", most))
    check(emu.read(9 * 4, emu.memType.nesSpriteRam) == 0x19, "HUD at y=$19")
    -- 57 energy and 042 missiles: the tens column shows 5 over 4, the ones 7 over 2
    check(r(0x1C2) == 0x54 and r(0x1C3) == 0x72, string.format("digit columns show 5/4 and 7/2 (%02x %02x)", r(0x1C2), r(0x1C3)))
    -- the status bar is blank: no tile but the blank and the dot in rows 0-5
    local other = 0
    for a = 0x2000, 0x20BF do
      local t = emu.read(a, emu.memType.nesPpuMemory)
      if t ~= 0xFF and not (a == 0x20A1 and t == 0xFE) then other = other + 1 end
    end
    check(other == 0, "status bar blank (" .. other .. " other tiles)")
    -- palette 2 is Castlevania's again below the split
    check(emu.read(0x3F19, emu.memType.nesPpuMemory) == 0x37, "palette 2 back to Castlevania's after the split")
    done()
  end
end
