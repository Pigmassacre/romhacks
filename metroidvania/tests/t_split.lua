-- The status bar's last lines, under the HUD (y 42-47), stay black: the
-- palette change at the split doesn't show, whatever the timing of sprite 0.
local bad, frames = 0, 0
loadstate_raw("castle")
INPUT = function(f) local p = f % 60; return {right = p < 40, b = p % 6 == 0, a = p > 45 and p < 50} end
FRAME = function(f)
  if f % 7 == 0 and f > 10 then
    frames = frames + 1
    -- emu.getScreenBuffer: 256x240 ARGB
    local buf = emu.getScreenBuffer()
    for y = 42, 47 do
      for x = 0, 255 do
        local c = buf[y * 256 + x + 1] & 0xFFFFFF
        if c ~= 0 then bad = bad + 1; if bad < 4 then log(string.format("frame %d: colour %06x at %d,%d", f, c, x, y)) end end
      end
    end
  end
  if f == 600 then
    check(bad == 0, string.format("lines 42-47 black in %d frames (%d other pixels)", frames, bad))
    done()
  end
end
