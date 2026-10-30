-- The HUD's two rows above EN, as Castlevania's status bar had them: the time
-- under Metroid's "TIME", which counts down, and only while the screen is
-- locked for a boss, a tank and the boss's health. Each digit is compared
-- with the same digit of the energy, in the pattern table.
local function ppu(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function glyph(a) local t = {} for i = 0, 15 do t[#t + 1] = ppu(a + i) end return table.concat(t, ",") end
-- the column tiles: energy's top halves $0C, $0E; boss over time $10, $12, $14
local function energyGlyph(col) return glyph(0x0A0 + col * 0x20) end
local function topGlyph(col) return glyph(0x100 + col * 0x20) end
local function timeGlyph(col) return glyph(0x110 + col * 0x20) end
local blank = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
local time0
loadstate_raw("castle", function()
  w(0x43, 0x01); w(0x42, 0x37)                    -- time 137
  w(0x118, 0x03); w(0x117, 0x70)                  -- energy 37
end)
FRAME = function(f)
  w(0x118, 0x03); w(0x117, 0x70)
  w(0x5B, 0x40)
  if f == 20 then
    check(energyGlyph(1) ~= blank and energyGlyph(1) == timeGlyph(1), "the time's tens drawn (3, as the energy's)")
    check(energyGlyph(2) == timeGlyph(2), "and its ones (7)")
    check(topGlyph(0) == blank and topGlyph(1) == blank and topGlyph(2) == blank, "no boss row without a boss")
    time0 = r(0x42)
    w(0x48, 1); w(0x1A9, 37)                      -- the screen locked, the boss at 37
  end
  if f == 40 then
    check(topGlyph(0) ~= blank, "locked for a boss: the tank")
    check(energyGlyph(1) == topGlyph(1), "the boss's tens (3)")
    check(energyGlyph(2) == topGlyph(2), "and its ones (7)")
    w(0x48, 0)
  end
  if f == 60 then
    check(topGlyph(0) == blank, "the boss row goes with the lock")
  end
  if f == 150 then
    check(r(0x42) ~= time0, "the time runs")
    check((r(0x1CB) & 0x0F) == (r(0x42) >> 4) and (r(0x1CC) & 0x0F) == (r(0x42) & 0x0F), "and the HUD follows it")
    shot("rows"); done()
  end
end
