-- Write all of the game's RAM at each NMI, on either machine, for tools/ramdiff.py.
local M = SNES and emu.memType.snesMemory or emu.memType.nesMemory
local nmi = 0
local out = io.open(OUT .. (SNES and "snes.bin" or "nes.bin"), "wb")
local function on_nmi()
  nmi = nmi + 1
  local t = {}
  for a = 0, 0x7FF do t[a + 1] = string.char(emu.read(a, M)) end
  out:write(table.concat(t))
  if nmi >= FRAMES then out:close(); emu.stop(0) end
end
if SNES then
  for b = 0xA0, 0xBF do emu.addMemoryCallback(on_nmi, emu.callbackType.exec, b * 65536 + 0xE9C6, b * 65536 + 0xE9C6) end
else
  emu.addMemoryCallback(on_nmi, emu.callbackType.exec, 0xE9C6, 0xE9C6)
end
emu.addEventCallback(function() emu.setInput(PICK and PICK(nmi) or {}, 0) end, emu.eventType.inputPolled)
