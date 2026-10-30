-- Stage 10: the platform after x $300 carries Simon under a rock that leaves
-- 24 pixels above it, less than Samus's height. She has to be carried under it
-- as he is; she was once scraped off into the water.
local phase, t0, lastpx, far = "warp", 0, 0, 0
loadstate_raw("castle", function()
  w(0x28, 0x0A); w(0x29, 0x0A); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
INPUT = function(f) return phase == "fly" and pad("R") or {} end
local function x() return r(0x122) + 256 * r(0x123) end
local function platform()
  local s = r(0x2E) + 256 * r(0x2F)
  for p = 0x17, 0x1A do
    if r(0x434 + p) == 1 and r(0x31C + p) == 0xC9 and s + r(0x38C + p) >= 0x320 and s + r(0x38C + p) < 0x3C0 then
      return p, s + r(0x38C + p)
    end
  end
end
FRAME = function(f)
  w(0x118, 9); w(0x5B, 0x40); w(0x43, 3)
  if phase == "warp" and f > 120 and r(0x18) == 5 and r(0x19) == 6 then phase = "fly" end
  if phase == "fly" or phase == "hover" then
    w(0x1C0, 0x80); w(0x124, 0x80); w(0x10B, 0); w(0x109, 0)
    local p, px = platform()
    if p then
      phase = "hover"
      if px > lastpx and px < 0x350 then
        w(0x122, px % 256); w(0x123, px // 256)
        w(0x1C0, 0); phase = "drop"; t0 = f
      end
      lastpx = px
    end
    if f > 4000 then check(false, "the platform came"); done() end
  end
  if phase == "drop" then
    far = math.max(far, x())
    if far >= 0x380 and r(0x12A) ~= 0 then
      check(true, string.format("carried under the rock, to x %04x", far))
      shot("under")
      done()
    end
    if r(0x124) > 0xC0 then check(false, string.format("she fell in, at x %04x", x())); done() end
    if f > t0 + 800 then check(false, string.format("carried under the rock (got to %04x)", far)); done() end
  end
end
