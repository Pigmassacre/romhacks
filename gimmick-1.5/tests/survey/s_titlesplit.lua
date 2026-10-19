-- The title's lower half (below the panel) scrolls separately. Save it on a
-- few frames so tests/run.py's caller can compare the hack with the original.
NO_BOOT = true
BOOT_MAX = 100000
local f0 = 0
emu.addEventCallback(function()
  emu.setInput({start = (f0 >= 400 and f0 < 405)}, 0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  f0 = f0 + 1
  if f0 == 650 or f0 == 700 or f0 == 750 then shot((HACK and "hack" or "orig") .. f0) end
  if f0 == 751 then done() end
end, emu.eventType.endFrame)
