-- Castlevania's exit check is on the screen, not in the level: Simon only gets
-- that far over with the screen at the stage's end. Samus starts the stairs
-- off the middle, and Castlevania then moves her on the screen and not the
-- screen, so she came off the top of stage 1's last stairs already at the
-- door's place on the screen, with the screen short of the door: it opened
-- in the middle of the screen. The screen now keeps up on the stairs
-- (t_stairlong), and the door waits for the screen; here she's put back at
-- that place, off the stairs, to see it wait.
local function x() return r(0x122) + 256 * r(0x123) end
local function scroll() return r(0x2E) + 256 * r(0x2F) end
local phase, atTop, startAt, doorAt = "back", nil, nil, nil
loadstate_raw("stairs1")
INPUT = function(f)
  if phase == "back" then return pad("L") end
  if phase == "forth" then return pad("R") end
  if phase == "up" then return (f % 2 == 0) and pad("U") or {} end
  if phase == "climb" then return pad("U") end
  if phase == "right" then return pad("R") end
  return {}
end
FRAME = function(f)
  for i = 4, 0x13 do if r(0x434 + i) == 0x01 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  local a, mode = r(0x46C), r(0x18)
  local sx = (x() - scroll()) % 256
  if phase == "back" and x() < 0x4C0 then phase = "forth" end
  -- near the start of the stairs' foot, with the screen behind her
  if phase == "forth" and x() >= 0x50C then phase = "up"; startAt = sx end
  if phase == "up" and (a == 6 or a == 4) then phase = "climb" end
  if phase == "climb" and a == 0 and r(0x354) < 0x70 then
    phase = "right"
    local put = scroll() + 0xF2; w(0x122, put % 256); w(0x123, put // 256)   -- where the stairs once left her
    atTop = 0xF2
    log(string.format("started the stairs at screen x %02x, off them at %02x, scroll %04x", startAt, sx, scroll()))
  end
  if mode == 8 and not doorAt then
    doorAt = f
    check(atTop and atTop >= 0xEC, string.format("she came off the stairs far over (%02x)", atTop or 0))
    check(scroll() == 0x500, string.format("the door opens with the screen at the stage's end (%04x)", scroll()))
    check(x() >= 0x5E8, string.format("and with her at the door (%04x)", x()))
  end
  if doorAt and f == doorAt + 40 then shot("door"); done() end
  if f > 1500 then check(false, "through the door (" .. phase .. string.format(", x %04x)", x())); done() end
end
