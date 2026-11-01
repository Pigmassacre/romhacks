-- The title screen says "Gimmick! 1.5", ROMHACK BY PIGMASSACRE and AI SLOP - DO NOT PLAY: its background
-- uses the copied CHR pages $80-$83, and the "1.5" and notice tiles are in the
-- nametable. Starting the game from it still works.
NO_BOOT = true
BOOT_MAX = 100000
local f0, started = 0, false
emu.addEventCallback(function()
  -- skip the intro, then press Start on the title
  emu.setInput({start = (f0 >= 400 and f0 < 405) or (f0 >= 800 and not started and f0 % 60 < 5)}, 0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  f0 = f0 + 1
  if f0 == 700 then
    shot("title")
    local banks = string.format("%02x %02x %02x %02x", r(0xE5), r(0xE6), r(0xE7), r(0xE8))
    if HACK then
      check(banks == "80 81 82 83", "title background uses the copied pages (" .. banks .. ")")
      local t = emu.read(0x2000 + 9 * 32 + 24, emu.memType.nesPpuMemory)
      check(t ~= 0x01 and t ~= 0x10, string.format("the 1.5 is in the nametable (tile %02x at row 9, column 24)", t))
      check(emu.read(0x2000 + 6 * 32 + 1, emu.memType.nesPpuMemory) == 0x01, "the panel reaches column 1")
      -- the notice: letters on rows 1 and 2, starting together and centred as a
      -- block, and sky on the rows around them
      local function span(addr)
        local first, last = nil, nil
        for c = 0, 31 do
          if emu.read(addr + c, emu.memType.nesPpuMemory) ~= 0x10 then first = first or c; last = c end
        end
        return first, last
      end
      local f1, l1 = span(0x2020)
      local f2, l2 = span(0x2040)
      check(f1 == 5 and l1 == 26, string.format("ROMHACK BY PIGMASSACRE on row 1 (columns %s-%s)", f1, l1))
      check(f2 == 5 and l2 == 25, string.format("AI SLOP - DO NOT PLAY on row 2 (columns %s-%s)", f2, l2))
      check(span(0x2000) == nil and span(0x2060) == nil, "rows 0 and 3 are still sky")
      -- sprites 0 and 1 hide behind the white margins, as in the original
      local s0 = emu.read(3, emu.memType.nesSpriteRam)
      local s1 = emu.read(7, emu.memType.nesSpriteRam)
      check(s0 == 0x08 and s1 == 0xF0, string.format("sprites 0 and 1 on the new margins (x=%02x, %02x)", s0, s1))
    else
      check(banks == "00 65 66 67", "original: pages " .. banks)
      local sky = true
      for c = 0, 31 do
        if emu.read(0x2020 + c, emu.memType.nesPpuMemory) ~= 0x10 or emu.read(0x2040 + c, emu.memType.nesPpuMemory) ~= 0x10 then sky = false end
      end
      check(sky, "original: rows 1 and 2 are sky")
    end
  end
  if f0 > 800 and r(0x90) == 1 and not started then
    started = true
    check(r(0xE6) ~= 0x81, "the stage has its own CHR pages")
  end
  if f0 == 1600 then
    check(started, "Start begins the game")
    shot("stage")
    done()
  end
end, emu.eventType.endFrame)
