-- Skipping stones: throw the star out over the lake in stage 2, from the last
-- pillar before open water (column $1E), and ride it.
-- Hack: it skips off the water several times, carrying Yumetaro, then sinks.
-- Original: it sinks the first time it touches the water.

local skips, sank, lastvy, boarded = 0, false, 0, false
local maxx, alive_while_skipping = 0, true
GIN = {}
INPUT = function() return GIN end
local T = 90   -- frame the throw is let go
FRAME = warp(1, 0, function(f)
  GIN = {}
  for i = 2, 9 do w(0x90 + i, 0); w(0xD6 + i, 0) end   -- no rafts or enemies
  if f == 2 then w(0xB8, 0x1E); w(0xAE, 0x80); w(0xA4, 0x28); w(0x9A, 0); w(0xCC, 0); w(0xC2, 0) end
  if f > 3 and f < 8 then GIN = pad("R") end            -- face right
  if f >= T - 40 and f < T then GIN = pad("B") end      -- charge, let go on T
  if f >= T then
    local s = r(0x91)
    if f <= T + 200 then log(string.format("%3d %s", f, state())) end
    if s == 1 and lastvy > 0 and s8(r(0xC3)) < 0 and r(0x36F) < 0x80 then
      skips = skips + 1; log(string.format("  skip %d", skips))
      if skips == 1 and HACK then
        -- stand him on it
        w(0xB8, r(0xB9)); w(0xAE, r(0xAF))
        local y = r(0xA5) * 256 + r(0x9B) - 0xF0
        w(0xA4, y >> 8); w(0x9A, y % 256); w(0xC2, 0); w(0xCC, 0)
      end
    end
    if skips >= 1 and r(0x365) ~= 0 then boarded = true end
    if s == 1 and skips >= 2 and r(0x90) >= 0xD0 then alive_while_skipping = false end
    if s == 1 and r(0xB9) > maxx then maxx = r(0xB9) end
    if s == 0xD1 and not sank then sank = true; log(string.format("  sank at x=%02x", r(0xB9))) end
    lastvy = s8(r(0xC3))
    if f <= T + 150 and f % 3 == 0 then shot(string.format("%03d", f - T)) end
  end
  if f == T + 200 then
    if HACK then
      check(skips >= 4, string.format("the star skipped %d times", skips))
      check(boarded, "Yumetaro rode it")
      check(alive_while_skipping, "and stayed on it while it skipped")
      check(maxx >= 0x28, string.format("it carried him out to column %02x", maxx))
    else
      check(skips == 0, "original: no skips")
    end
    check(sank, "it sank in the end")
    done()
  end
end)
