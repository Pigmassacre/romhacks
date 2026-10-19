-- Survey: where are the tube tiles ($7E00 attribute == $30) in each stage?
local stage = 0
local function survey(f)
  if f == 30 then
    local hits = {}
    for x = 0, 127 do
      for s = 0, 3 do
        for row = 0, 11 do
          local t = tile(x, s * 16 + row)
          if r(0x7E00 + t) == 0x30 then hits[#hits + 1] = string.format("%02x/%x%x", x, s, row) end
        end
      end
    end
    log(string.format("stage %d start x=%02x y=%02x: %d tube tiles: %s", stage, r(0xB8), r(0xA4), #hits, table.concat(hits, " ", 1, math.min(#hits, 30))))
    stage = stage + 1
    if stage > 6 then done() return end
    FRAME = warp(stage, 0, survey)
  end
end
FRAME = warp(0, 0, survey)
