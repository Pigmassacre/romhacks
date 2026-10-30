-- The ending: object slot 0 is the castle falling, drawn by Castlevania in
-- sprite palette 0, and there is no status bar. The hack once drew Samus
-- there in its place, in her colours, with sprite 0 a black square over the
-- sky. Stage 18 is cleared by hand, as the orb would.
local phase = "wait"
loadstate_raw("castle", function() w(0x28, 18); w(0x46, 1); w(0x18, 0x0C); w(0x19, 0) end)
FRAME = function(f)
  if r(0x18) == 0x0F and r(0x19) >= 3 and phase == "wait" then
    phase = "seen"
    shot("ending")
    local castle = 0
    for i = 17, 63 do
      if emu.read(i * 4, emu.memType.nesSpriteRam) < 0xEF then castle = castle + 1 end
    end
    check(castle > 0, string.format("the castle's sprites drawn (%d)", castle))
    check(emu.read(0, emu.memType.nesSpriteRam) >= 0xEF, "no sprite 0")
    check(emu.read(0x3F11, emu.memType.nesPpuMemory) ~= 0x16, "sprite palette 0 isn't Samus's")
    done()
  end
  if f > 2000 then check(false, string.format("the ending came (mode %02x/%02x)", r(0x18), r(0x19))); done() end
end
