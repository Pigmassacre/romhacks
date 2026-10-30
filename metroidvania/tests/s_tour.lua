-- Not a test: a tour of every stage, for looking at. For each stage, Samus
-- is dropped in (by dying with the stage set), stands, then flies right
-- through the walls; screenshots go to out/test/tour_<stage>_<n>.png.
-- TOUR_FROM and TOUR_TO pick the stages.
local stage, phase, t0, n = tonumber(os.getenv("TOUR_FROM") or "1"), "warp", 0, 0
local last = tonumber(os.getenv("TOUR_TO") or "18")
local function warp()
  w(0x28, stage); w(0x29, stage); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
  phase = "warp"
end
loadstate_raw("castle", warp)
INPUT = function(f) return phase == "fly" and pad("R") or {} end
FRAME = function(f)
  if phase ~= "warp" then w(0x118, 9) end
  if phase == "warp" and f > 60 and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == stage and (r(0x126) & 1) == 1 then
    phase = "stand"; t0 = f; n = 0
  end
  if phase == "stand" and f == t0 + 90 then
    shot(string.format("%02d_0", stage))
    log(string.format("stage %d: x %02x%02x y %02x scroll %02x%02x", stage, r(0x123), r(0x122), r(0x124), r(0x2F), r(0x2E)))
    phase = "fly"; t0 = f; Y = r(0x124) - 0x18
  end
  if phase == "fly" then
    w(0x1C0, 0x80); w(0x124, Y); w(0x10B, 0); w(0x109, 0); w(0x5B, 0x40)
    if (f - t0) % 150 == 149 then n = n + 1; shot(string.format("%02d_%d", stage, n)) end
    if f - t0 > 150 * 8 or r(0x28) ~= stage or r(0x18) ~= 5 then
      w(0x1C0, 0)
      log(string.format("  end: x %02x%02x mode %02x stage %d", r(0x123), r(0x122), r(0x18), r(0x28)))
      stage = stage + 1
      if stage > last then log("PASS"); done() return end
      warp()
    end
  end
  if f > 60000 then log("FAIL stuck in " .. phase .. " at stage " .. stage); done() end
end
