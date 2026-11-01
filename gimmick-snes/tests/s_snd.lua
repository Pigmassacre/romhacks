-- How the game uses the sound hardware. tools/survey.py --snd
M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function poke(a, v) emu.write(a, v, emu.memType.nesDebug) end
local nmi, cmd, bC, sb = 0, 0, 0, 0
local dpcm, hist, sbh = {}, {}, {}
local regs = {}
for i = 0, 0x17 do regs[i] = 0 end
local function bump(t, k) t[k] = (t[k] or 0) + 1 end
emu.addMemoryCallback(function(a, v)
  if a < 0xA000 then cmd = v & 15
  elseif a < 0xC000 then if cmd == 11 then bC = v end
  elseif a < 0xE000 then sb = v & 15
  else bump(sbh, string.format("%X %02X", sb, sb < 6 and 0 or v)) end
end, emu.callbackType.write, 0x8000, 0xFFFF)
emu.addMemoryCallback(function(a, v)
  local i = a - 0x4000
  regs[i] = v
  if i == 0 or i == 4 then bump(hist, string.format("r%X lc=%d", i, (v >> 4) & 3))
  elseif i == 1 or i == 5 then bump(hist, string.format("r%X sw=%d", i, v >> 7))
  elseif i == 8 then bump(hist, string.format("r8 c=%d lin=%d", v >> 7, v & 127 > 0 and 1 or 0))
  elseif i == 0xC then bump(hist, string.format("rC lc=%d", (v >> 4) & 3))
  elseif i == 0xE then bump(hist, string.format("rE mode=%d", v >> 7))
  elseif i == 0x10 then bump(hist, string.format("r10 %02X", v))
  elseif i == 0x11 then bump(hist, string.format("r11 %02X", v))
  elseif i == 0x15 then
    bump(hist, string.format("r15 %02X", v))
    if v & 0x10 ~= 0 then bump(dpcm, string.format("%02X %02X %02X %02X", bC, regs[0x12], regs[0x13], regs[0x10])) end
  end
end, emu.callbackType.write, 0x4000, 0x4015)
emu.addMemoryCallback(function()
  nmi = nmi + 1
  if ON_NMI then ON_NMI(nmi) end
  if FRAMES and nmi >= FRAMES then
    local h = io.open(OUT .. "snd.txt", "w")
    for k, n in pairs(dpcm) do h:write("D ", k, " ", n, "\n") end
    for k, n in pairs(hist) do h:write("H ", k, " ", n, "\n") end
    for k, n in pairs(sbh) do h:write("S ", k, " ", n, "\n") end
    h:close(); emu.stop(0)
  end
end, emu.callbackType.exec, 0xE9C6, 0xE9C6)
emu.addEventCallback(function() emu.setInput(PICK_INPUT and PICK_INPUT(nmi) or {}, 0) end, emu.eventType.inputPolled)
