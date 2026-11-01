-- Take screenshots at set NMIs, on either machine. tools/shots.py writes OUT, AT and
-- whether this is the SNES build above this file.
local M = SNES and emu.memType.snesMemory or emu.memType.nesMemory
function r(a) return emu.read(a, M) end
local nmi, i = 0, 1
local NMI_AT = 0xE9C6
local log = io.open(OUT .. "log.txt", "w")
local function on_nmi()
  nmi = nmi + 1
  if nmi % 100 == 0 then
    log:write(string.format("%d 90=%02X F0=%02X 1B=%02X 4A=%02X 28=%02X FF=%02X FE=%02X\n", nmi, r(0x90), r(0xF0), r(0x1B), r(0x4A), r(0x28), r(0xFF), r(0xFE))); log:flush()
  end
end
if SNES then
  for b = 0xA0, 0xBF do
    emu.addMemoryCallback(on_nmi, emu.callbackType.exec, b * 65536 + NMI_AT, b * 65536 + NMI_AT)
  end
else
  emu.addMemoryCallback(on_nmi, emu.callbackType.exec, NMI_AT, NMI_AT)
end
emu.addEventCallback(function()
  local inp = PICK and PICK(nmi) or {}
  emu.setInput(inp, 0)
end, emu.eventType.inputPolled)
local frames = 0
emu.addEventCallback(function()
  frames = frames + 1
  if nmi >= AT[i] then
    local h = io.open(OUT .. string.format("%s_%06d.png", SNES and "snes" or "nes", AT[i]), "wb")
    h:write(emu.takeScreenshot()); h:close()
    i = i + 1
    if not AT[i] then log:close(); emu.stop(0) end
  end
  if frames > (MAX_FRAMES or 3000) then
    local h = io.open(OUT .. "timeout.png", "wb"); h:write(emu.takeScreenshot()); h:close()
    local st = emu.getState()
    log:write(string.format("timeout at nmi %d pc=%02X:%04X a=%02X x=%02X y=%02X sp=%04X\n", nmi, st["cpu.k"], st["cpu.pc"], st["cpu.a"], st["cpu.x"], st["cpu.y"], st["cpu.sp"])); log:close(); emu.stop(1)
  end
end, emu.eventType.endFrame)
