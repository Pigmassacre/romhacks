-- Recall a star that is travelling through a tube (status 2): stage 1 has a
-- tunnel into a tube at column $3D, row 9.
-- GIN set in FRAME(f) is the input for frame f + 1.

local T = 150          -- the throw is let go on this frame
local intube, recalled = nil, nil
local seen = {}
GIN = {}
INPUT = function() return GIN end
FRAME = function(f)
  GIN = {}
  for i = 2, 9 do w(0x90 + i, 0); w(0xD6 + i, 0) end   -- no enemies
  if f == 2 then w(0xB8, 0x39); w(0xAE, 0x80); w(0xA4, 0x1A); w(0x9A, 0); w(0xCC, 0) end
  if f >= T - 40 and f < T then GIN = pad("B") end
  if f >= T then
    local s = r(0x91)
    seen[s] = true
    if s == 2 and not intube then intube = f; log(string.format("in the tube on frame %d at x=%02x.%02x y=%02x.%02x", f, r(0xB9), r(0xAF), r(0xA5), r(0x9B))) end
    if intube and f == intube + 3 then GIN = pad("B") end
    if intube and f == intube + 4 then
      if HACK then
        check(r(0x91) == 0x80, string.format("B recalls it from the tube ($91=%02x)", r(0x91)))
        recalled = f
      else
        check(r(0x91) == 2, "original: it stays in the tube")
      end
    end
    if recalled and f > recalled and f < recalled + 45 then GIN = pad("B") end   -- charge the new one
    if recalled and f == recalled + 30 then
      check(r(0x3C9) & 0x20 == 0, "the new star is drawn in front of the background")
    end
    if recalled and f == recalled + 46 then check(r(0x91) == 1, "the new star is thrown normally") end
    if f % 4 == 0 and f < T + 120 then log(string.format("%3d %s flags=%02x", f, state(), r(0x3C9))) end
  end
  if f == T + 120 then
    check(intube ~= nil, "the first star went into the tube")
    done()
  end
end
