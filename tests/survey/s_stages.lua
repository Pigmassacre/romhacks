-- Survey: warp to each stage (by dying with $1B set) and list its water tiles.
-- Not a pass/fail test.
local stage, phase, t0 = 0, "warp", 0
FRAME = function(f)
  if phase == "warp" then
    w(0x1B, stage); w(0x1C, 0); w(0x346, 0); w(0x104, 9)
    phase = "dying"; t0 = f
  elseif phase == "dying" then
    if r(0x90) == 1 and f > t0 + 60 then phase = "play"; t0 = f end
    if f > t0 + 2000 then log("stuck warping to " .. stage); done() end
  elseif phase == "play" and f == t0 + 30 then
    local water, lethal = {}, {}
    for t = 0, 255 do
      if r(0x7D00 + t) == 0 then
        if r(0x7F00 + t) ~= 0 then water[#water + 1] = string.format("%02x", t) else lethal[#lethal + 1] = string.format("%02x", t) end
      end
    end
    log(string.format("stage %d (level byte %02x, cp %02x) start x=%02x.%02x y=%02x.%02x", stage, r(0x1B), r(0x1C), r(0xB8), r(0xAE), r(0xA4), r(0x9A)))
    log("  water tiles: " .. table.concat(water, " "))
    log("  other lethal: " .. table.concat(lethal, " "))
    -- where is water in the map?
    local wset = {}
    for _, h in ipairs(water) do wset[tonumber(h, 16)] = true end
    local hits = {}
    for x = 0, 127 do
      for s = 0, 3 do
        for row = 1, 11 do
          local t = tile(x, s * 16 + row)
          if wset[t] then hits[#hits + 1] = string.format("%02x/%x%x", x, s, row); break end
        end
      end
    end
    log("  water at (x/screen,row): " .. table.concat(hits, " ", 1, math.min(#hits, 40)))
    shot(tostring(stage))
    stage = stage + 1
    if stage > 6 then done() return end
    phase = "warp"
  end
end
