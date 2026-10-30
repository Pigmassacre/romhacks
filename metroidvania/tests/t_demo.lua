-- The attract demo: Samus plays it, with Metroid's HUD over a blank status
-- bar, and it ends back on the title with her energy full again.
local drawn, hud, seen, back = 0, 0, false, false
local function samus_sprites()
  local n = 0
  for i = 17, 63 do
    local y, t = emu.read(i * 4, emu.memType.nesSpriteRam), emu.read(i * 4 + 1, emu.memType.nesSpriteRam)
    if y < 0xEF and t % 2 == 0 and (t < 0x40 or (t >= 0x46 and t < 0x50) or (t >= 0x52 and t < 0x60) or (t >= 0x6A and t < 0x70)) then n = n + 1 end
  end
  return n
end
FRAME = function(f)
  if r(0x18) == 2 and r(0x19) == 1 then
    seen = true
    if samus_sprites() > 0 then drawn = drawn + 1 end
    if emu.read(9 * 4, emu.memType.nesSpriteRam) == 0x19 then hud = hud + 1 end
    if f % 300 == 0 then w(0x118, 0x05) end       -- energy spent, to see it refilled
  end
  if seen and r(0x18) == 1 and not back then
    back = true
    check(drawn > 300, string.format("Samus drawn in the demo (%d frames)", drawn))
    check(hud > 300, string.format("the HUD up (%d frames)", hud))
    check(r(0x118) == 0x09 and r(0x117) == 0x90, string.format("on the title, her energy full again (%02x%02x)", r(0x118), r(0x117)))
    done()
  end
  if f > 4000 then check(false, "the demo came and went (seen " .. tostring(seen) .. ")"); done() end
end
