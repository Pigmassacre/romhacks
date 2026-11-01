-- Not a test: every sprite pose Castlevania has, four to a screenshot, on stage
-- 1's first screen, in out/test/gallery_<rom>_<pose>.png. Runs on both ROMs;
-- tools/gallery_diff.py then names the poses that look different in the hack:
--   python3 tests/run.py gallery
--   python3 tests/run.py --rom "Castlevania I.nes" gallery
--   python3 tools/gallery_diff.py
local tag = HACK and "hack" or "orig"
local pose, phase, t0 = 0, "title", 0
local AT = {{4, 0x38, 0x58}, {5, 0x90, 0x58}, {6, 0x38, 0x88}, {7, 0x90, 0x88}}
INPUT = function(f) if phase == "title" then return {start = f % 120 < 3 and f > 60} end return {} end
FRAME = function(f)
  w(0x5B, 0x40)
  if phase == "title" and r(0x18) == 5 and r(0x19) == 6 then phase = "wait"; t0 = f end
  if phase == "wait" and f == t0 + 90 then phase = "poses"; t0 = f end
  if phase ~= "title" and phase ~= "wait" or phase == "wait" then
    for s = 1, 0x1B do
      w(0x434 + s, 0); w(0x300 + s, 0); w(0x31C + s, 0); w(0x450 + s, 0)
    end
    w(0x42, 0x99)     -- the time
  end
  if phase == "poses" then
    for k, a in ipairs(AT) do
      w(0x31C + a[1], pose + k - 1); w(0x38C + a[1], a[2]); w(0x354 + a[1], a[3]); w(0x338 + a[1], 0)
    end
    if (f - t0) % 6 == 5 then
      shot(string.format("%s_%02x", tag, pose))
      pose = pose + #AT
      if pose > 0xFF then log("PASS"); done(); return end
    end
  end
  if f > 8000 then log("FAIL stuck in " .. phase); done() end
end
