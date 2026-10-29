-- Castlevania's stairs: up pressed at the foot of them (a new press: held,
-- it is aiming), and Castlevania's stair code takes Samus up (actions 6 and
-- 4), drawn on the steps, running, to the stage's exit at the top. Walking
-- past them with up held doesn't climb.
local seen6, seen4, maxdx, back = false, false, 0, false
loadstate_raw("stairs1")
local passed, phase, t0 = true, "past", 0
local function x() return r(0x122) + 256 * r(0x123) end
INPUT = function(f)
  if phase == "past" then return pad("L U") end  -- past the foot of the stairs, aiming up
  if phase == "back" then return pad("R") end    -- back to it
  if phase == "wait" then return {} end
  if phase == "up" then return f < 560 and pad("U") or {} end
  return {}
end
FRAME = function(f)
  w(0x5B, 0x40)                                   -- the hall's zombies don't knock her away
  local a = r(0x46C)
  if phase == "past" and (a == 6 or a == 4) then passed = false end
  if phase == "past" and x() < 0x4F0 then phase = "back" end
  if phase == "back" and x() >= 0x50C then phase = "wait"; t0 = f end   -- up starts them from $504 to $51C
  if phase == "wait" and f > t0 + 10 then phase = "up" end
  if a == 6 then seen6 = true end
  if a == 4 then
    seen4 = true
    -- drawn where Castlevania has Simon: its idea of his x matches the screen
    local world = r(0x40) + 256 * r(0x41)
    local screen = r(0x38C) + r(0x2E) + 256 * r(0x2F)
    maxdx = math.max(maxdx, math.abs(world - screen))
  end
  if f == 300 then shot("stairs") end
  if f == 600 then
    check(passed, "walking past with up held doesn't climb")
    check(seen6 and seen4, "up starts the stairs (actions 6, then 4)")
    check(maxdx <= 1, "on the stairs, Simon's x and his screen x agree (off by " .. maxdx .. ")")
    -- these stairs lead to the stage's exit: the next stage starts (mode 8)
    check(a == 0 and r(0x18) == 8, string.format("the stage's exit at the top (mode %02x)", r(0x18)))
    check(r(0x124) < 0x70, string.format("at the top floor (y=%02x)", r(0x124)))
    done()
  end
end
