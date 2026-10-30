-- Out of energy: Metroid's explosion while Castlevania's death plays, then
-- Castlevania brings Samus back with full energy. With no lives left, the
-- Game Over screen has Castlevania's font back. Continuing puts Samus's
-- tiles back over the font, with the dot sprite 0 hits (a continue doesn't
-- load the stage's graphics again: they were once left out), while the
-- screen is black.
local exploded, phase, lit = false, "die", 0
loadstate_raw("castle", function() w(0x2A, 1) end)   -- the last life
INPUT = function(f) return (phase == "over" and f % 40 == 0) and pad("S") or {} end   -- continue
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
  end
  if phase == "over" and r(0x18) == 5 then phase = "load" end
  if phase == "load" and r(0x19) >= 1 and r(0x19) <= 3 then
    local buf = emu.getScreenBuffer()
    for i = 1, #buf do if (buf[i] & 0xFFFFFF) ~= 0 then lit = lit + 1 end end
  end
  if phase == "load" and r(0x19) == 6 then
    local p = function(a) return emu.read(a, emu.memType.nesPpuMemory) end
    check(p(0x1D03) == 0x03 and p(0x1D04) == 0x0F and p(0x1D07) == 0x33, "after continuing, Samus's tiles over the font")
    check(p(0x1FE0) == 0x80, "and the dot sprite 0 hits")
    check(lit == 0, string.format("the screen black while the stage loaded (%d pixels lit)", lit))
    done()
  end
  if f == 3000 then check(false, "Game Over (" .. phase .. ")"); done() end
end
