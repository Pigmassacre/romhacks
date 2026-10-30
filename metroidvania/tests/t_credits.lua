-- The credits end with "AND THE HERO", and name her.
local P = emu.memType.nesPpuMemory
local SAMUS = {0x84, 0x60, 0x78, 0x88, 0x84, 0x54, 0x60, 0x82, 0x60, 0x7A}
loadstate_raw("castle", function() w(0x28, 18); w(0x46, 1); w(0x18, 0x0C); w(0x19, 0) end)
FRAME = function(f)
  if r(0x18) == 0x0F and f % 30 == 0 then
    for row = 0, 29 do
      for c = 0, 22 do
        local ok = true
        for i, t in ipairs(SAMUS) do if emu.read(0x2000 + row * 32 + c + i - 1, P) ~= t then ok = false; break end end
        if ok then
          check(true, string.format("Samus Aran, on row %d, from column %d", row, c))
          check(c == 5, "in the middle of the line Simon's name filled")
          shot("hero")
          done()
          return
        end
      end
    end
  end
  if f > 9000 then check(false, "her name came"); done() end
end
