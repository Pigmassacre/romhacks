-- Do two star sounds on different SFX tracks layer? Queue them alone and together.
SETS = {{0x11}, {0x64}, {0x6d}, {0x14}, {0x12}, {0x17}, {0x1c}, {0x20}}
local reg, last5b = {}, nil
emu.addMemoryCallback(function(a, v)
  if a < 0xE000 then last5b = v elseif last5b then reg[last5b] = v end
end, emu.callbackType.write, 0xC000, 0xFFFF)
local idx, start, cur = 0, 0, nil
FRAME = function(f)
  if f % 80 == 10 then w(0x56 + r(0x5A), 0x1F); w(0x5A, r(0x5A) + 1) end
  if cur and f > start and f <= start + 30 then
    local cp = (reg[4] or 0) + ((reg[5] or 0) % 16) * 256
    log(string.format("  %-8s t=%2d C p=%03x v=%02x", cur, f - start, cp, (reg[10] or 0) % 32))
  end
  if f % 80 == 20 then
    idx = idx + 1
    if idx > #SETS then done() return end
    start = f; cur = ""
    for _, id in ipairs(SETS[idx]) do
      local wi = r(0x5A); w(0x56 + wi, id); if wi < 3 then w(0x5A, wi + 1) end
      cur = cur .. string.format("%02x", id) .. "+"
    end
  end
end
