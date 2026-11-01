-- The tour of the whole game on either machine, with screenshots. tools/tour.py.
local M = SNES and emu.memType.snesMemory or emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function poke(a, v) emu.write(a, v, SNES and emu.memType.snesWorkRam or emu.memType.nesDebug) end
function DUMP_NT(what)
  local t = {}
  for a = 0, 0xFFF do
    if SNES then t[#t + 1] = string.char(emu.read(0xC000 + a, emu.memType.snesVideoRam))
    else t[#t + 1] = string.char(emu.read(0x2000 + a, emu.memType.nesPpuMemory)) end
  end
  local h = io.open(OUT .. "nt_" .. what .. ".bin", "wb"); h:write(table.concat(t)); h:close()
  if SNES and what == DUMP_ALL then
    h = io.open(OUT .. "vram.bin", "wb"); t = {}
    for a = 0, 0xFFFF do t[#t + 1] = string.char(emu.read(a, emu.memType.snesVideoRam)) end
    h:write(table.concat(t)); h:close()
    h = io.open(OUT .. "wram.bin", "wb"); t = {}
    for a = 0, 0x1FFF do t[#t + 1] = string.char(emu.read(a, emu.memType.snesMemory)) end
    h:write(table.concat(t)); h:close()
    local st = emu.getState()
    h = io.open(OUT .. "regs.txt", "w")
    local keys = {}
    for k, v in pairs(st) do if k:match("^ppu%.layers%[0%]") or k:match("^ppu%.[vh]") or k:match("mainScreen") or k:match("^ppu%.scanline") then keys[#keys + 1] = k .. "=" .. tostring(v) end end
    table.sort(keys)
    h:write(table.concat(keys, " "), "\n")
    local q = ""
    for a = 0, 0x5F do q = q .. string.format("%02X ", emu.read(a, emu.memType.snesMemory)) end
    h:write(string.format("FD=%02X FC=%02X FF=%02X 42=%02X 43=%02X 44=%02X F0=%02X 29=%02X\n", r(0xFD), r(0xFC), r(0xFF), r(0x42), r(0x43), r(0x44), r(0xF0), r(0x29)))
    h:close()
  end
  h = io.open(OUT .. "st_" .. what .. ".txt", "w")
  h:write(string.format("FC=%02X FD=%02X FF=%02X A4=%02X B8=%02X 90=%02X", r(0xFC), r(0xFD), r(0xFF), r(0xA4), r(0xB8), r(0x90)))
  h:close()
end
local nmi = 0
local function on_nmi()
  nmi = nmi + 1
  if ON_NMI then ON_NMI(nmi) end
  if FRAMES and nmi >= FRAMES then emu.stop(0) end
end
if SNES then
  for b = 0xA0, 0xBF do emu.addMemoryCallback(on_nmi, emu.callbackType.exec, b * 65536 + 0xE9C6, b * 65536 + 0xE9C6) end
else
  emu.addMemoryCallback(on_nmi, emu.callbackType.exec, 0xE9C6, 0xE9C6)
end
emu.addEventCallback(function()
  local inp = PICK_INPUT and PICK_INPUT(nmi) or {}
  if SNES then inp.b, inp.y = inp.a, inp.b; inp.a = nil end
  emu.setInput(inp, 0)
end, emu.eventType.inputPolled)
