-- The splash effect plays the star's sink frames $1B-$22, two game frames each.
-- Drives the effect directly: start a splash in slot 1 and read the frame the
-- star draw routine shows for it.
local seen = {}
local SPLASH = SYM.STAR_FRAME_SPLASH
emu.addMemoryCallback(function()
  -- DrawMetasprite with slot 1 standing in for the splash: record the frame
  if rs("FX_T", 1) ~= 0 and r(0x9B) == 0x70 and r(0xA5) == 0x19 then
    seen[#seen + 1] = r(0x301)
  end
end, emu.callbackType.exec, 0xF468, 0xF468)
FRAME = function(f)
  if not HACK then done() return end
  if f == 10 then
    -- a splash at x=06.00, y=19.70, as a skip would leave
    w(SYM.FX_Kind + 1, 1); w(SYM.FX_T + 1, 1)
    w(SYM.FX_YSub + 1, 0x70); w(SYM.FX_YTile + 1, 0x19)
    w(SYM.FX_XSub + 1, 0); w(SYM.FX_XTile + 1, 6)
  end
  if f == 40 then
    local want = {}
    for t = 1, SYM.SPLASH_LEN do want[t] = SPLASH + (t - 1) // 2 end
    local got = table.concat(seen, " ", 1, math.min(#seen, 20))
    log("frames: " .. got)
    check(#seen == SYM.SPLASH_LEN, string.format("drawn on %d frames", #seen))
    local ok = true
    for t = 1, #want do if seen[t] ~= want[t] then ok = false end end
    check(ok, "frames $1B $1B $1C $1C ... $22 $22")
    done()
  end
end
