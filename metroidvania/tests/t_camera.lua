-- Off the middle of the screen (Castlevania's stairs leave her there), the
-- screen catches up with Samus a pixel a frame, up to the stage's limits. She
-- once stayed at the far side, with nothing to see ahead of her.
local x0, s0
local function x() return r(0x122) + 256 * r(0x123) end
local function scroll() return r(0x2E) + 256 * r(0x2F) end
local function sx() return (x() - scroll()) % 256 end
local phase = "start"
loadstate_raw("castle", function() end)
FRAME = function(f)
  for i = 4, 0x13 do if r(0x434 + i) == 0x01 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  if f == 5 then
    -- further along, the way stairs would leave her
    x0 = x() + 0xC0; w(0x122, x0 % 256); w(0x123, x0 // 256); s0 = scroll()
    local here = sx()
    check(here > 0x80, string.format("she starts off to the right (%02x)", here))
    phase = "right"
  end
  if phase == "right" and f == 10 then
    check(scroll() == s0 + 5, string.format("a pixel a frame (%d in 5)", scroll() - s0))
  end
  if phase == "right" and f == 200 then
    check(sx() == 0x8F, string.format("the screen caught up, to the edge of the middle (%02x)", sx()))
    check(x() == x0, "she didn't move")
    x0 = x() - 0x30; w(0x122, x0 % 256); w(0x123, x0 // 256); s0 = scroll()
    phase = "left"
  end
  if phase == "left" and f == 400 then
    check(sx() == 0x71, string.format("and back the other way (%02x, scroll %04x)", sx(), scroll()))
    check(x() == x0, "she didn't move")
    done()
  end
end
