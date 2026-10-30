-- The picture under the status bar stays put when the game runs late. The
-- split gives the PPU the picture's address and turns the screen back on, so
-- a split on any other line moves the whole screen up or down. It waits for
-- sprite 0, and a late frame's NMI used to land after the frame's sprites had
-- put sprite 0 in place and write Castlevania's over it: a crowd made the
-- screen jump. The screen comes back on at the end of line 44, every frame.
local on, bad, late, seen0 = 0, 0, 0, 0
local log0 = 0
emu.addMemoryCallback(function(a, v)
  local s = emu.getState()
  local l = s["ppu.scanline"]
  if v ~= 0 and l >= 0 and l < 240 and r(0x18) == 5 and r(0x19) == 6 then
    on = on + 1
    if l ~= 44 then
      bad = bad + 1
      if bad < 6 then log(string.format("frame %d: the screen came back on on line %d", F, l)) end
    end
  end
end, emu.callbackType.write, 0x2001, 0x2001)
emu.addMemoryCallback(function() late = late + 1 end, emu.callbackType.exec, 0xC0C0, 0xC0C0)
loadstate_raw("castle")
INPUT = function(f) local p = f % 90; return {right = p < 70, b = p % 6 == 0, a = p > 45 and p < 55} end
FRAME = function(f)
  w(0x45, 0x40)                 -- she stays alive in the crowd
  if f == 2500 then
    check(late > 20, string.format("the game ran late (%d frames)", late))
    check(on > 2000, string.format("the split seen (%d frames)", on))
    check(bad == 0, string.format("always on line 44 (%d frames not)", bad))
    done()
  end
end
