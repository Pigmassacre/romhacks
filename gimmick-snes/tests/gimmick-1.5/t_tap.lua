-- Tap to summon: Select switches it on and off. In tap mode a tap of B starts
-- a star, which keeps charging with B up, and another tap throws it.

local function charging() return r(0x91) >= 0x80 and r(0x91) < 0xD0 end
local function tap(f, frames)
  for _, t in ipairs(frames) do if f == t then return true end end
  return false
end

local hold = {
  name = "hold mode (default): a tap does nothing",
  len = 40,
  input = function(f) return tap(f, {5}) and pad("B") or {} end,
  frame = function(f)
    if f == 5 then check(charging(), "charging while B is down") end
    if f == 8 then check(r(0x91) == 0, "and dropped when it is let go") end
    if f == 10 then check(rs("Tap_Mode") == 0, "tap mode is off") end
  end,
}

local taps = {
  name = "tap mode: tap to summon, tap to throw",
  len = 120,
  input = function(f)
    if f == 2 then return pad("E") end                       -- Select
    return tap(f, {5, 70}) and pad("B") or {}
  end,
  frame = function(f)
    if f == 2 and HACK then check(rs("Tap_Mode") == 1, "Select turns tap mode on") end
    if f == 60 and HACK then check(r(0x91) == 0xA9, string.format("still charging with B up ($91=%02x)", r(0x91))) end
    if f == 70 and HACK then check(r(0x91) == 1, "the second tap throws it") end
    if f == 69 and not HACK then check(r(0x91) == 0, "original: the tap is dropped") end
  end,
}

local early = {
  name = "tap mode: an early second tap throws as soon as it can",
  len = 60,
  input = function(f)
    if f == 2 then return pad("E") end
    return tap(f, {5, 12}) and pad("B") or {}
  end,
  frame = function(f)
    if not HACK then return end
    if f == 20 then check(charging(), "still charging after the early tap") end
    -- the charge starts at $80 on frame 5 and reaches $A0 on frame 37; the
    -- next frame's B test sees it ready and lets go
    if f == 37 then check(r(0x91) == 0xA0, "ready") end
    if f == 38 then check(r(0x91) == 1, string.format("thrown as soon as it is ready ($91=%02x)", r(0x91))) end
  end,
}

local recall = {
  name = "tap mode: a tap recalls the star",
  len = 120,
  input = function(f)
    if f == 2 then return pad("E") end
    return tap(f, {5, 45, 70}) and pad("B") or {}
  end,
  frame = function(f)
    if not HACK then return end
    if f == 50 then check(r(0x91) == 1, "thrown") end
    if f == 70 then check(charging(), "the tap recalls it and starts a new one") end
    if f == 110 then check(charging(), "which keeps charging with B up") end
  end,
}

local off = {
  name = "Select again: back to hold mode",
  len = 30,
  input = function(f)
    if f == 2 or f == 10 then return pad("E") end
    return tap(f, {15}) and pad("B") or {}
  end,
  frame = function(f)
    if f == 12 then check(rs("Tap_Mode") == 0, "tap mode is off again") end
    if f == 18 then check(r(0x91) == 0, "a tap does nothing again") end
  end,
}

SCENARIOS = { hold, taps, early, recall, off }
run_scenarios()
