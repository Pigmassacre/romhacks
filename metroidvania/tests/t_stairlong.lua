-- Dracula's stage's stairs span two floors. Started off the middle of the
-- screen, Castlevania moved Samus along the screen and not the screen; going
-- down them she ran off its edge, her x wrapped round, and she was left on the
-- stairs on a floor that doesn't exist. On the stairs the screen now catches
-- up: she keeps on the screen, comes out on floor 0, and walks on.
local function x() return r(0x122) + 256 * r(0x123) end
local function scroll() return r(0x2E) + 256 * r(0x2F) end
local phase, t0, died, maxsx, moved = "warp", 0, false, 0, 0
loadstate_raw("castle", function()
  w(0x28, 18); w(0x29, 18); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
local dir
INPUT = function(f)
  if phase == "up" then return pad("U") end
  if phase == "fly" or phase == "out" or phase == "walk" then return dir end
  if phase == "down" then return pad("D") end
  return {}
end
FRAME = function(f)
  if phase ~= "warp" then w(0x118, 9); w(0x5B, 0x40); w(0x43, 4) end
  if r(0x18) == 6 then died = true end
  if phase == "warp" and died and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 18 and (r(0x126) & 1) == 1 then
    phase = "fly"; t0 = f
    died = false
  end
  if phase == "fly" then                         -- to the stairs' foot on floor 0
    w(0x1C0, 0x80); w(0x124, 0x60); w(0x10B, 0); w(0x109, 0)
    local d = 0x29F - x()
    dir = d > 0 and pad("R") or pad("L")
    if math.abs(d) <= 2 then w(0x122, 0x9F); w(0x123, 2); w(0x124, 0x6D); w(0x1C0, 0); phase = "land"; t0 = f end
  end
  if phase == "land" and f == t0 + 25 then phase = "up"; t0 = f end
  if phase == "up" and r(0x46C) == 0 and r(0x46) == 1 and f > t0 + 30 then
    -- on floor 1, at the top of the way back. Back off to the right of the
    -- middle's band: walking left, then right, to have the screen behind her
    phase = "fly2"; t0 = f
  end
  if phase == "fly2" then
    w(0x1C0, 0x80); w(0x124, 0x81); w(0x10B, 0); w(0x109, 0)
    phase = "out"; t0 = f
  end
  if phase == "out" then
    w(0x1C0, 0x80); w(0x124, 0x81); w(0x10B, 0); w(0x109, 0)
    dir = pad("L"); if x() < 0x1E8 then phase = "walk"; t0 = f end
  end
  if phase == "walk" then
    dir = pad("R")
    w(0x1C0, 0x80); w(0x124, 0x81); w(0x10B, 0); w(0x109, 0)
    if x() >= 0x21F then
      w(0x122, 0x22); w(0x123, 2); w(0x124, 0x8D); w(0x1C0, 0); phase = "land2"; t0 = f
      log(string.format("at the top: x %04x screen x %02x", x(), r(0x38C)))
    end
  end
  if phase == "land2" and f == t0 + 25 then
    check(r(0x38C) >= 0x8A, string.format("she starts them to the right of the middle (%02x)", r(0x38C)))
    phase = "down"; t0 = f
  end
  if phase == "down" then
    if r(0x19) == 6 then
      maxsx = math.max(maxsx, r(0x38C))
      if r(0x46C) == 4 then moved = moved + 1; local world = r(0x40) + 256 * r(0x41); if math.abs(world - (r(0x38C) + scroll())) > 1 then check(false, "Castlevania's x and hers agree") end end
    end
    if f == t0 + 40 then check(r(0x38C) <= 0x81, string.format("the screen has caught up (%02x)", r(0x38C))) end
    if r(0x46C) == 0 and moved > 20 then
      check(maxsx < 0xA8, string.format("she stays on the screen, to the stage's end at most (%02x)", maxsx))
      check(r(0x46) == 0, string.format("she comes out on floor 0 (%d)", r(0x46)))
      check(r(0x124) >= 0x6C and r(0x124) <= 0x74, string.format("on its ground (y %02x)", r(0x124)))
      check(x() >= 0x298 and x() <= 0x2A8, string.format("at the stairs' foot (x %04x)", x()))
      done()
    end
    if f > t0 + 700 then check(false, "off the stairs: floor " .. r(0x46)); done() end
  end
  if f > 6000 then check(false, string.format("got there (%s, x %04x floor %d)", phase, x(), r(0x46))); done() end
end
