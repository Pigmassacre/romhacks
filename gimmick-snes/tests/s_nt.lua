-- At game frame COUNT (the game's own counter at $ED,$EE, past the title), write the
-- nametables, palette and scroll, for tools/ntdiff.py.
local M = SNES and emu.memType.snesMemory or emu.memType.nesMemory
local nmi, passes = 0, 0
local prev = 0
local function on_nmi()
  nmi = nmi + 1
  if emu.read(0x90, M) ~= 0 and emu.read(0xF0, M) == 0xAC then
    passes = passes + 1
    if passes == COUNT then
      local h = io.open(OUT .. (SNES and "snes_nt.bin" or "nes_nt.bin"), "wb")
      local t = {}
      if SNES then
        for a = 0, 0xFFF do t[#t + 1] = string.char(emu.read(0xE000 + a, emu.memType.snesVideoRam)) end
      else
        for a = 0, 0xFFF do t[#t + 1] = string.char(emu.read(0x2000 + a, emu.memType.nesPpuMemory)) end
      end
      h:write(table.concat(t)); h:close()
      h = io.open(OUT .. (SNES and "snes_st.txt" or "nes_st.txt"), "w")
      h:write(string.format("nmi=%d ED=%02X%02X FC=%02X FD=%02X FF=%02X 1B=%02X\n", nmi, emu.read(0xEE, M), emu.read(0xED, M), emu.read(0xFC, M), emu.read(0xFD, M), emu.read(0xFF, M), emu.read(0x1B, M)))
      h:close()
      emu.stop(0)
    end
  end
end
if SNES then
  for b = 0xA0, 0xBF do emu.addMemoryCallback(on_nmi, emu.callbackType.exec, b * 65536 + 0xE9C6, b * 65536 + 0xE9C6) end
else
  emu.addMemoryCallback(on_nmi, emu.callbackType.exec, 0xE9C6, 0xE9C6)
end
local BTN = SNES and {jump = "b", shoot = "y"} or {jump = "a", shoot = "b"}
emu.addEventCallback(function()
  if emu.read(0x90, M) == 0 then
    emu.setInput({start = nmi % 60 < 5}, 0)
  else
    local i = {right = passes % 400 < 300, left = passes % 400 >= 320 and passes % 400 < 390}
    i[BTN.jump] = passes % 53 < 20
    i[BTN.shoot] = passes % 150 < 60
    emu.setInput(i, 0)
  end
end, emu.eventType.inputPolled)
