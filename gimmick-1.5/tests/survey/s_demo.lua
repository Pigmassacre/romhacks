-- Frames for a demo GIF (tools/demo_gif.py): a throw and a recall on stage 1,
-- then a star skipping across stage 2's lake with Yumetaro on it.
GIN = {}
INPUT = function() return GIN end
local n = 0
local function grab() n = n + 1; shot(string.format("%04d", n)) end
local phase = "recall"
local water
local skips, lastvy = 0, 0
FRAME = function(f)
  GIN = {}
  if phase == "recall" then
    if f < 40 then GIN = pad("B") end                 -- charge, throw on 40
    if f >= 62 and f < 100 then GIN = pad("B") end    -- recall on 62, charge
    if f >= 100 and f < 106 then GIN = pad("R") end
    if f >= 20 and f <= 150 then grab() end
    if f == 150 then phase = "water"; water = warp(1, 0, function(g)
      GIN = {}
      for i = 2, 9 do w(0x90 + i, 0); w(0xD6 + i, 0) end
      if g == 2 then w(0xB8, 0x1E); w(0xAE, 0x80); w(0xA4, 0x28); w(0x9A, 0); w(0xCC, 0) end
      if g > 3 and g < 8 then GIN = pad("R") end
      if g >= 50 and g < 90 then GIN = pad("B") end
      if g >= 80 then
        if r(0x91) == 1 and lastvy > 0 and s8(r(0xC3)) < 0 and r(0x36F) < 0x80 then
          skips = skips + 1
          if skips == 1 then
            w(0xB8, r(0xB9)); w(0xAE, r(0xAF))
            local y = r(0xA5) * 256 + r(0x9B) - 0xF0
            w(0xA4, y >> 8); w(0x9A, y % 256); w(0xC2, 0); w(0xCC, 0)
          end
        end
        lastvy = s8(r(0xC3))
        grab()
      end
      if g == 215 then done() end
    end) end
  else
    water(f)
  end
end
