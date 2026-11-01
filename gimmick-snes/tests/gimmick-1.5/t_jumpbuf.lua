-- Jump buffering: jump, then tap A shortly before landing.
-- In the hack the tap becomes a jump on the first frame he can jump, if it
-- was less than JUMPBUF_FRAMES frames ago. In the original game it is lost.

local BUF = SYM.JUMPBUF_FRAMES
local L      -- frame on which he lands (found by the first scenario)

local function jumpinput(f, tap, hold)
  if f >= 1 and f <= 25 then return pad("A") end   -- a full jump
  if tap and (f == tap or (hold and f > tap)) then return pad("A") end
  return {}
end

local function landed(f)
  return f > 5 and r(0x36E) >= 0x80
end

local calib = {
  name = "calibrate: one jump, no tap",
  len = 70,
  input = function(f) return jumpinput(f) end,
  frame = function(f)
    if not L and landed(f) then L = f; log("lands on frame " .. f) end
    if f == 69 then check(L ~= nil, "landed") end
  end,
}

-- Tap A on frame L + d. He can next jump on frame L + 1.
local function scenario(d, expect, hold)
  local tap, jumped
  return {
    name = string.format("%s A %d frames before landing", hold and "press and hold" or "tap", -d),
    len = 70,
    setup = function() tap = L + d; jumped = false end,
    input = function(f) return jumpinput(f, tap, hold) end,
    frame = function(f)
      local want = expect and (HACK or d >= 1)   -- a press on L+1 is a plain jump
      if f == L + 1 then
        jumped = s8(r(0xC2)) < 0   -- a tap gives a short hop: A is up again, so vy is cut to -24
        log(string.format("%3d %s", f, state()))
        check(jumped == want, string.format("A at L%+d: jump on landing = %s (want %s)", d, tostring(jumped), tostring(want)))
      end
      if hold and want and f == L + 12 then
        check(r(0xA4) * 256 + r(0x9A) < 0x1900, "holding A gives a full jump")
      end
    end,
  }
end

SCENARIOS = { calib }
for d = -(BUF + 1), 1 do
  -- The tap and the frame he can jump on (L + 1) must be less than BUF frames apart.
  SCENARIOS[#SCENARIOS + 1] = scenario(d, (1 - d) < BUF)
end
SCENARIOS[#SCENARIOS + 1] = scenario(-3, true, true)
run_scenarios()
