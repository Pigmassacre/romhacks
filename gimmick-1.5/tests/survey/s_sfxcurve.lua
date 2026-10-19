-- Per-frame pitch and volume of a few sound effects (sq1 and 5B channel C).
IDS = {0x16, 0x44, 0x15, 0x10, 0x13, 0x0f, 0x14}
local reg, cur, start, last5b = {}, nil, 0, nil
emu.addMemoryCallback(function(a, v) reg[a] = v end, emu.callbackType.write, 0x4000, 0x4013)
emu.addMemoryCallback(function(a, v)
  if a < 0xE000 then last5b = v elseif last5b then reg[0x100 + last5b] = v end
end, emu.callbackType.write, 0xC000, 0xFFFF)
local idx, line = 0, ""
FRAME = function(f)
  if f % 60 == 10 then w(0x56 + r(0x5A), 0x1F); w(0x5A, r(0x5A) + 1) end
  if cur and f > start and f <= start + 40 then
    local sqp = (reg[0x4002] or 0) + ((reg[0x4003] or 0) % 8) * 256
    local sqv = (reg[0x4000] or 0) % 16
    local cp = (reg[0x104] or 0) + ((reg[0x105] or 0) % 16) * 256
    local cv = (reg[0x10A] or 0) % 32
    local mix = reg[0x107] or 0xFF
    local con = (mix & 4) == 0 and "C" or "-"
    log(string.format("  %02x t=%2d sq1 p=%03x v=%x | 5bC p=%03x v=%02x %s", cur, f - start, sqp, sqv, cp, cv, con))
  end
  if f % 60 == 20 then
    idx = idx + 1
    if idx > #IDS then done() return end
    cur = IDS[idx]; start = f
    local wi = r(0x5A)
    w(0x56 + wi, cur); if wi < 3 then w(0x5A, wi + 1) end
  end
end
