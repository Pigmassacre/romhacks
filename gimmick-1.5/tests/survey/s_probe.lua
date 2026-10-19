-- Dump the sprite CHR banks and palettes during stage 1 (for tools/render_frames.py).
FRAME = function(f)
  if f == 30 then
    local s = "chr"
    for a = 0xE1, 0xE8 do s = s .. string.format(" %02x", r(a)) end
    log(s)
    local p = "pal"
    for i = 0, 31 do p = p .. string.format(" %02x", emu.read(0x3F00 + i, emu.memType.nesPpuMemory)) end
    log(p)
    local c = "ctrl " .. string.format("%02x", r(0xFF))
    log(c)
    done()
  end
end
