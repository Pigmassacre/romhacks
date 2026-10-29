-- Metroid's sound effects: jumping writes Metroid's jump sound to square 1
-- (from src/sfxdata.asm, recorded in Metroid), and Castlevania's music
-- keeps off the channel until it ends.
local writes = {}
local rec = false
emu.addMemoryCallback(function(a, v)
  if rec then writes[#writes + 1] = {F, a, v} end
end, emu.callbackType.write, 0x4000, 0x4003)
loadstate_raw("castle")
INPUT = function(f) return (f >= 10 and f < 14) and pad("A") or {} end
FRAME = function(f)
  if f == 9 then rec = true end
  if f == 40 then
    local first = nil
    for _, wr in ipairs(writes) do if wr[2] == 0x4001 and wr[3] == 0x8C then first = wr[1] break end end
    check(first ~= nil, "jump sound's sweep ($4001 = $8C) written")
    if first then
      local seq = {}
      for _, wr in ipairs(writes) do if wr[1] == first then seq[#seq + 1] = string.format("%x=%02x", wr[2] - 0x4000, wr[3]) end end
      check(table.concat(seq, " ") == "0=95 1=8c 2=40 3=b9", "first frame as Metroid's: " .. table.concat(seq, " "))
      local other = 0
      for _, wr in ipairs(writes) do if wr[1] > first and wr[1] < first + 12 then other = other + 1 end end
      check(other == 0, "nothing else on square 1 for 11 frames (" .. other .. ")")
    end
    done()
  end
end
