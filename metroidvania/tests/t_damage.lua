-- Castlevania's enemies hurt Samus as Metroid's would: a zombie's touch takes
-- 12 energy (8 of Simon's 64 health, times 1.5) with Metroid's knockback,
-- blinking and invincibility, and Simon's health stays at $20.
local hit, e0, x0, invin = nil, 0, 0, 0
loadstate_raw("castle")
INPUT = function(f) return f < 400 and not hit and pad("R") or {} end
local function energy() return (r(0x118) & 0x0F) * 10 + (r(0x117) >> 4) end
FRAME = function(f)
  if f == 1 then e0 = energy() end
  if not hit and energy() < e0 then
    hit = f; x0 = r(0x122) + 256 * r(0x123)
    log(string.format("hit at frame %d, energy %d -> %d", f, e0, energy()))
    check(e0 - energy() == 12, "a zombie takes 12 energy")
    check(r(0x113) == 0x32 - 1 or r(0x113) == 0x32, string.format("50 frames invincible (%02x)", r(0x113)))
    check(r(0x109) >= 0xFC, "knocked up (speed y negative)")
    check(r(0x45) == 0x20, "SimonHP kept at $20")
  end
  if hit and f == hit + 10 then
    local x = r(0x122) + 256 * r(0x123)
    check(x < x0, "knocked back, away from the zombie")
  end
  if hit and f == hit + 60 then
    check(r(0x113) == 0, "invincibility over")
    done()
  end
  if f == 600 then check(false, "a zombie touched Samus"); done() end
end
