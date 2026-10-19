-- Screenshots of the title screen (not a pass/fail test). Boot only.
NO_BOOT = true
BOOT_MAX = 100000
local f0 = 0
emu.addEventCallback(function()
  f0 = f0 + 1
  if f0 % 150 == 0 and f0 <= 2400 then shot(string.format("%04d", f0)) end
  if f0 == 2401 then done() end
end, emu.eventType.endFrame)
