-- Dump the title screen: a screenshot, the nametables, the CHR bank registers and
-- the palette, to out/test/titledump.*. Press Start once to skip the intro.
NO_BOOT = true
BOOT_MAX = 100000
local f0 = 0
emu.addEventCallback(function()
  emu.setInput({start = (f0 >= 400 and f0 < 405)}, 0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  f0 = f0 + 1
  if f0 == 700 then
    shot("700")
    local h = io.open(OUT .. "titledump.bin", "wb")
    local t = {}
    for a = 0x2000, 0x2FFF do t[#t + 1] = string.char(emu.read(a, emu.memType.nesPpuMemory)) end
    for a = 0, 31 do t[#t + 1] = string.char(emu.read(a, emu.memType.nesPaletteRam)) end
    h:write(table.concat(t)); h:close()
    local s = "chr"
    for a = 0xE1, 0xE8 do s = s .. string.format(" %02x", r(a)) end
    log(s .. string.format(" ctrl=%02x scrollx=%02x scrolly=%02x mask=%02x bank8000=%02x bankA000=%02x", r(0xFF), r(0xFD), r(0xFC), r(0xFE), r(0x40), r(0x41)))
    local st = emu.getState()
    local m = "mapper chr:"
    for k, v in pairs(st) do if tostring(k):find("chrReg") or tostring(k):find("chrBank") or tostring(k):find("Chr") then m = m .. " " .. k .. "=" .. tostring(v) end end
    log(m)
    done()
  end
end, emu.eventType.endFrame)
