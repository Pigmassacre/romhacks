-- Castlevania's moving platforms (stage 10 has them over water): Samus can
-- stand on one and is carried along. She is flown over the water (through
-- walls, the hack's debug flag) until one is on the screen, then put above
-- it while it moves left (moving right, it carries her into a rock), and
-- dropped.
local phase, t0, rode, x0, px0, lastpx = "warp", 0, 0, 0, 0, 0
loadstate_raw("castle", function()
  w(0x28, 0x0A); w(0x29, 0x0A); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
INPUT = function(f) return phase == "fly" and pad("R") or {} end
-- (hovering: no input, Samus stays where she is)
local function platform()
  for x = 0x17, 0x1A do
    if r(0x434 + x) == 1 and r(0x31C + x) == 0xC9 then return x end
  end
end
FRAME = function(f)
  w(0x118, 9)
  if phase == "warp" and f > 120 and r(0x18) == 5 and r(0x19) == 6 then phase = "fly" end
  if phase == "fly" or phase == "hover" then
    w(0x1C0, 0x80); w(0x124, 0x80); w(0x10B, 0); w(0x109, 0)
    local p = platform()
    if p then
      phase = "hover"
      local px = r(0x38C + p) + r(0x2E) + 256 * r(0x2F)
      if px < lastpx and r(0x38C + p) > 0x60 and r(0x38C + p) < 0xE0 then
        w(0x122, px % 256); w(0x123, px // 256)
        w(0x1C0, 0); phase = "drop"; t0 = f
      end
      lastpx = px
    end
    if f > 3000 then check(false, "a platform came under Samus"); done() end
  end
  if phase == "drop" then
    local p = platform()
    if r(0x12A) ~= 0 then
      rode = rode + 1
      if rode == 1 then x0 = r(0x122) + 256 * r(0x123); px0 = r(0x38C + r(0x12A)) + r(0x2E) end
      if rode == 90 then
        local x = r(0x122) + 256 * r(0x123)
        local px = r(0x38C + r(0x12A)) + r(0x2E)
        check(true, "Samus landed on a platform")
        check(x - x0 == px - px0, string.format("she moved with it (%d, it %d)", x - x0, px - px0))
        check(r(0x124) + r(0x101) == r(0x354 + r(0x12A)), "standing on its top")
        shot("riding"); done()
      end
    elseif rode > 0 then
      check(false, "she stayed on the platform (fell off after " .. rode .. " frames)"); done()
    end
    if f > t0 + 200 and rode == 0 then check(false, string.format("Samus landed on a platform (y %02x)", r(0x124))); shot("missed"); done() end
  end
end
