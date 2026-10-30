-- The HUD's colours (sprite palette 2) go in every frame, as the split puts
-- Castlevania's back every frame. They were once left out on late frames
-- (the game logic overran, and the NMI doesn't flush the update buffer), and
-- after a long update buffer, and the HUD flashed in Castlevania's colours.
-- Every 16th frame is made late ($1B), every 16th has a long, harmless entry
-- in the buffer (blank tiles for the status bar), and a pixel of the HUD's E
-- is watched on the screen every frame.
local bad, first, long, late = 0, nil, 0, 0
local function w0(a, v) emu.write(a, v, emu.memType.nesDebug) end
loadstate_raw("castle")
FRAME = function(f)
  w(0x118, 9); w(0x5B, 0x40)
  w0(0x1B, 0)                                     -- (what the NMI we cut short would have done)
  if f < 40 then return end
  local p = emu.getScreenBuffer()[26 * 256 + 0x18 + 2 + 1] & 0xFFFFFF   -- the E's top row
  first = first or p
  if p ~= first then bad = bad + 1 end
  if f % 16 == 0 then
    w0(0x1B, 1); late = late + 1
  elseif f % 16 == 8 then
    local y = r(0x20) - 1                         -- ($CCEE left a 0 at the end, and moved past it)
    if y >= 0 and y < 0x40 then
      w0(0x700 + y, 1); w0(0x701 + y, 0x24); w0(0x702 + y, 0x20)
      for i = 0, 0x8F do w0(0x703 + y + i, 0) end
      w0(0x793 + y, 0xFF); w0(0x794 + y, 0)
      w0(0x20, y + 0x95)
      long = long + 1
    end
  end
  if f == 500 then
    check(late > 20 and long > 20, string.format("%d late frames, %d long buffers", late, long))
    check(bad == 0, string.format("the HUD kept its colours (%d frames didn't)", bad))
    done()
  end
end
