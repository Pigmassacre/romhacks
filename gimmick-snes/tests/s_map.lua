-- Capture the world map's nametable and palette, after clearing each stage, for the
-- SNES's Mode 7 version of it. tools/survey.py --map
local M = emu.memType.nesMemory
local nmi, stage, phase, t0 = 0, 0, "boot", 0
local function poke(a, v) emu.write(a, v, emu.memType.nesDebug) end
local inp = {}
emu.addEventCallback(function() emu.setInput(inp, 0) end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  nmi = nmi + 1
  inp = {}
  local on_map = emu.read(0x4A, M) == 0 and emu.read(0x90, M) == 1 and emu.read(0xE5, M) == 0x54
  if phase == "boot" then
    inp.start = emu.read(0x90, M) == 0 and nmi % 60 < 5
    if emu.read(0x90, M) == 1 and nmi > 600 then phase = "clear" end
  elseif phase == "clear" then
    poke(0x1B, stage); poke(0x54, 0); poke(0xEB, 1); poke(0xEA, 1); poke(0x104, 9)
    phase = "wait"; t0 = nmi
  elseif phase == "wait" then
    if on_map and nmi > t0 + 60 then
      local t = {}
      for a = 0, 0x7FF do t[#t + 1] = string.char(emu.read(0x2000 + a, emu.memType.nesPpuMemory)) end
      for a = 0, 31 do t[#t + 1] = string.char(emu.read(0x3F00 + a, emu.memType.nesPpuMemory)) end
      local h = io.open(OUT .. string.format("map_%d.bin", stage), "wb"); h:write(table.concat(t)); h:close()
      h = io.open(OUT .. string.format("map_%d.txt", stage), "w")
      h:write(string.format("FC=%02X FD=%02X FF=%02X chr=%02X,%02X,%02X,%02X,%02X,%02X,%02X,%02X", emu.read(0xFC, M), emu.read(0xFD, M), emu.read(0xFF, M), emu.read(0xE1, M), emu.read(0xE2, M), emu.read(0xE3, M), emu.read(0xE4, M), emu.read(0xE5, M), emu.read(0xE6, M), emu.read(0xE7, M), emu.read(0xE8, M)))
      h:close()
      phase = "press"; t0 = nmi
    elseif nmi > t0 + 1500 then phase = "press"; t0 = nmi end
  elseif phase == "press" then
    inp.start = nmi % 60 < 5
    if not on_map and emu.read(0x90, M) == 1 and nmi > t0 + 60 then
      stage = stage + 1
      if stage > 5 then emu.stop(0) end
      phase = "clear"
    end
  end
end, emu.callbackType.exec, 0xE9C6, 0xE9C6)
