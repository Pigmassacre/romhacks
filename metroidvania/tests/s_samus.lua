-- Not a test: every frame Samus has, facing both ways, for looking over. On stage
-- 1's first screen, with what she stands on in view: out/test/samus_<frame>_<dir>.png
-- and a line in the log with where she was.
local seen = {}
local n = 0
local INPUTS = {}
for _, s in ipairs({
  {30, ""}, {40, "R"}, {30, "L"}, {20, "R B"}, {20, "L B"}, {50, "R A"}, {50, "L A"}, {50, "A"},
  {50, "R A B"}, {30, "L A B"}, {20, "U"}, {20, "U B"}, {20, "R U"}, {20, "R U B"}, {20, "L U"}, {20, "L U B"},
  {50, "R U A"}, {50, "L U A"}, {40, "A U B"}, {6, "D"}, {30, "R"}, {30, "L"}, {6, ""}, {6, "U"}, {20, ""},
  {4, "E"}, {10, ""}, {6, "B"}, {20, ""}, {6, "U B"}, {20, ""}, {30, "R A B"}, {20, ""},
}) do for i = 1, s[1] do INPUTS[#INPUTS + 1] = s[2] end end
local start
loadstate_raw("castle", function() start = F end)
INPUT = function(f)
  if not start then return {} end
  local s = INPUTS[f - start]
  return pad(s)
end
FRAME = function(f)
  if not start then return end
  w(0x71, 20)
  if f - start < 3 then return end
  local key = r(0x103) * 2 + r(0x111)
  if not seen[key] then
    seen[key] = true
    n = n + 1
    log(string.format("frame %02x dir %d: x %02x y %02x", r(0x103), r(0x111), (r(0x122) - r(0x2E)) & 255, r(0x124)))
    shot(string.format("%02x_%d", r(0x103), r(0x111)))
  end
  if f - start > #INPUTS then log(n .. " frames"); log("PASS"); done() end
end
