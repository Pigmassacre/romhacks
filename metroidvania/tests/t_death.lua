-- Out of energy: Metroid's explosion while Castlevania's death plays, then
-- Castlevania brings Samus back with full energy. With no lives left, the
-- Game Over screen has Castlevania's font back.
local exploded, phase = false, "die"
loadstate_raw("castle", function() w(0x2A, 1) end)   -- the last life
FRAME = function(f)
  if f == 5 then w(0x118, 0); w(0x117, 0x10); w(0x45, 0) end
  if r(0x46C) == 8 and r(0x100) == 8 then exploded = true end
  if f == 20 then shot("explode") end
  if phase == "die" and r(0x18) == 0x0D and r(0x1F) == 0 then
    phase = "over"
    check(exploded, "Samus exploded")
    -- the font: Castlevania's "A" ($E0 in the background table) is back
    local a = {}
    for i = 0, 7 do a[#a + 1] = emu.read(0x1E00 + i, emu.memType.nesPpuMemory) end
    check(table.concat(a, ",") ~= "0,0,0,0,0,0,0,0", "font back for Game Over")
    shot("gameover")
    done()
  end
  if f == 2000 then check(false, "Game Over (" .. phase .. ")"); done() end
end
