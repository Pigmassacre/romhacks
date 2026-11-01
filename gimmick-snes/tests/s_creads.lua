-- Does the CPU read $C000-$DFFF, or only the DPCM channel? tools/survey.py --creads
M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function poke(a, v) emu.write(a, v, emu.memType.nesDebug) end
local pc, seen, nmi = 0, {}, 0
emu.addMemoryCallback(function(a) pc = a end, emu.callbackType.exec, 0x8000, 0xFFFF)
emu.addMemoryCallback(function(a)
  if a ~= pc then seen[pc * 65536 + a] = (seen[pc * 65536 + a] or 0) + 1 end
end, emu.callbackType.read, 0xC000, 0xDFFF)
emu.addMemoryCallback(function()
  nmi = nmi + 1
  if ON_NMI then ON_NMI(nmi) end
  if FRAMES and nmi >= FRAMES then
    local h = io.open(OUT .. "creads.txt", "w")
    for k, n in pairs(seen) do h:write(string.format("%04X %04X %d\n", k // 65536, k % 65536, n)) end
    h:close(); emu.stop(0)
  end
end, emu.callbackType.exec, 0xE9C6, 0xE9C6)
emu.addEventCallback(function() emu.setInput(PICK_INPUT and PICK_INPUT(nmi) or {}, 0) end, emu.eventType.inputPolled)
