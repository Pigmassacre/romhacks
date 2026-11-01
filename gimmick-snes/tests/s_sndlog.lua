-- Log what each sound channel is doing at each NMI, on either machine, for
-- tools/sounddiff.py. On the SNES that is the DSP's registers; on the NES, the APU's
-- state and the 5B registers as written.
local M = SNES and emu.memType.snesMemory or emu.memType.nesMemory
local nmi, passes = 0, 0
local out = io.open(OUT .. (SNES and "snd_snes.txt" or "snd_nes.txt"), "w")
local sb, sbr = 0, {}
for i = 0, 15 do sbr[i] = 0 end
if not SNES then
  emu.addMemoryCallback(function(a, v)
    if a < 0xE000 then sb = v & 15 else sbr[sb] = v end
  end, emu.callbackType.write, 0xC000, 0xFFFF)
end
local function on_nmi()
  nmi = nmi + 1
  if emu.read(0x90, M) ~= 0 and emu.read(0xF0, M) == 0xAC then passes = passes + 1 end
  local t = {}
  if SNES then
    local D = emu.memType.spcDspRegisters
    for v = 0, 7 do
      local b = v * 16
      t[#t + 1] = emu.read(b, D) .. "," .. (emu.read(b + 2, D) + emu.read(b + 3, D) * 256) .. "," .. emu.read(b + 4, D)
    end
    t[#t + 1] = emu.read(0x6C, D) & 31
  else
    local s = emu.getState()
    local function sq(n)
      local p = "apu.square" .. n
      local en = s[p .. ".envelope.lengthCounter.counter"] > 0
      local vol = s[p .. ".envelope.constantVolume"] and s[p .. ".envelope.volume"] or s[p .. ".envelope.counter"]
      local per = s[p .. ".realPeriod"]
      if not en or per < 8 or per > 0x7FF then vol = 0 end
      return vol .. "," .. per .. "," .. s[p .. ".duty"]
    end
    t[#t + 1] = sq(1); t[#t + 1] = sq(2)
    local tr = "apu.triangle"
    local on = s[tr .. ".lengthCounter.counter"] > 0 and s[tr .. ".linearCounter"] > 0
    t[#t + 1] = (on and 1 or 0) .. "," .. s[tr .. ".timer.period"] .. ",0"
    local nz = "apu.noise"
    local nv = s[nz .. ".envelope.constantVolume"] and s[nz .. ".envelope.volume"] or s[nz .. ".envelope.counter"]
    if s[nz .. ".envelope.lengthCounter.counter"] == 0 then nv = 0 end
    t[#t + 1] = nv .. "," .. s[nz .. ".timer.period"] .. ",0"
    t[#t + 1] = (s["apu.dmc.bytesRemaining"] > 0 and 1 or 0) .. "," .. s["apu.dmc.timer.period"] .. ",0"
    for v = 0, 2 do
      local on5 = (sbr[7] >> v) & 1 == 0
      local vol = on5 and (sbr[8 + v] & 15) or 0
      t[#t + 1] = vol .. "," .. (sbr[v * 2] + (sbr[v * 2 + 1] & 15) * 256) .. ",0"
    end
    t[#t + 1] = s[nz .. ".timer.period"]
  end
  out:write(nmi, " ", table.concat(t, " "), "\n")
  if nmi >= FRAMES then out:close(); emu.stop(0) end
end
if SNES then
  for b = 0xA0, 0xBF do emu.addMemoryCallback(on_nmi, emu.callbackType.exec, b * 65536 + 0xE9C6, b * 65536 + 0xE9C6) end
else
  emu.addMemoryCallback(on_nmi, emu.callbackType.exec, 0xE9C6, 0xE9C6)
end
emu.addEventCallback(function()
  local inp
  if emu.read(0x90, M) == 0 then inp = {start = nmi % 60 < 5} else
    inp = {right = passes % 400 < 300, left = passes % 400 >= 320 and passes % 400 < 390}
    inp[SNES and "b" or "a"] = passes % 53 < 20
    inp[SNES and "y" or "b"] = passes % 150 < 60
  end
  emu.setInput(inp, 0)
end, emu.eventType.inputPolled)
