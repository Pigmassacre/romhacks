-- While a stage loads the screen is black. The hack used to write sprite
-- palette 0 after Castlevania's update buffer each frame; while loading,
-- that buffer runs past the vertical blank with the screen off, when the
-- PPU shows the colour its address points at, and the writes showed as a
-- line. Samus dies with the stage set to 2, and the stage loads.
local phase, frames, lit = "die", 0, 0
loadstate_raw("castle", function()
  w(0x28, 2); w(0x29, 2); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
FRAME = function(f)
  if r(0x18) == 5 and r(0x19) >= 1 and r(0x19) <= 3 then
    frames = frames + 1
    local buf = emu.getScreenBuffer()
    for i = 1, #buf do
      if (buf[i] & 0xFFFFFF) ~= 0 then lit = lit + 1 end
    end
  end
  if r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 2 and frames > 0 then
    check(frames >= 10, string.format("the stage loaded (%d frames)", frames))
    check(lit == 0, string.format("the screen stayed black while it loaded (%d pixels lit)", lit))
    done()
  end
  if f > 1000 then check(false, "the stage loaded"); done() end
end
