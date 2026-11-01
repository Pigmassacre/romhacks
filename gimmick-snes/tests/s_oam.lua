-- Which sprite tile tables does the game use, and which sprites sit below the split?
M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function poke(a, v) emu.write(a, v, emu.memType.nesDebug) end
local nmi, odd, even, low = 0, 0, 0, {}
local lowtiles = {}
emu.addMemoryCallback(function()
  nmi = nmi + 1
  for i = 0, 63 do
    local y, t = r(0x200 + i * 4), r(0x201 + i * 4)
    if y < 0xEF then
      if t & 1 == 1 then odd = odd + 1 else even = even + 1 end
      if y >= 190 then lowtiles[t] = (lowtiles[t] or 0) + 1 end
    end
  end
  if ON_NMI then ON_NMI(nmi) end
  if FRAMES and nmi >= FRAMES then
    local h = io.open(OUT .. "oam.txt", "w")
    h:write("odd ", odd, " even ", even, "\n")
    for t, n in pairs(lowtiles) do h:write(string.format("%02X %d\n", t, n)) end
    h:close(); emu.stop(0)
  end
end, emu.callbackType.exec, 0xE9C6, 0xE9C6)
emu.addEventCallback(function() emu.setInput(PICK_INPUT and PICK_INPUT(nmi) or {}, 0) end, emu.eventType.inputPolled)
