-- Not a test: makes the savestates the tests start from, in out/test/.
--   castle  Samus standing still in stage 1 (the hall), just after it starts
--   stairs1 Samus standing by the hall's first stairs, at the end of the hall
local phase, t0, lastx, still = "title", 0, 0, 0
local function playing() return r(0x18) == 5 and r(0x19) == 6 and (r(0x126) & 1) == 1 and r(0x10B) == 0 end
INPUT = function(f)
  if phase == "title" then return {start = (f % 120) < 3 and f > 60} end
  if phase == "walk" or phase == "hall" then
    local i = {right = true}
    if f % 40 < 3 then i.b = true end
    if f % 300 < 20 then i.a = true end
    return i
  end
  return {}
end
FRAME = function(f)
  if phase == "title" and r(0x18) == 5 then phase = "walk" end
  if phase == "walk" and r(0x28) == 1 and playing() then phase = "castle"; t0 = f end
  if phase == "castle" and f == t0 + 20 then savestate("castle"); phase = "hall" end
  if phase == "hall" then
    local x = r(0x122) + 256 * r(0x123)
    if x == lastx and playing() then still = still + 1 else still = 0 end
    lastx = x
    if still > 40 and x > 0x580 then phase = "stairs"; t0 = f end
  end
  if phase == "stairs" and f == t0 + 30 then savestate("stairs1") end
  if phase == "stairs" and f == t0 + 35 then
    log(string.format("stairs1 at x=%04x", lastx))
    log("PASS"); done()
  end
  if f > 6000 then log("FAIL did not get there (" .. phase .. ")"); done() end
end
