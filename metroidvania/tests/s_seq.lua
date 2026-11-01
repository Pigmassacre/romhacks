-- Not a test: what the rest of the game shows around Samus, with no bot and no
-- cheats, a frame every so often for looking at: dying, a hit, a whip upgrade, the
-- invisibility potion, in out/test/seq_<what>_<n>.png.
local SEQS = {
  {name = "die", set = function() w(0x118, 0); w(0x117, 0x10); w(0x45, 0) end, every = 5, len = 60},
  {name = "hurt", set = function() w(0x45, 0x18) end, every = 3, len = 36},
  {name = "whip", set = function() local s = 10; w(0x434 + s, 0x2F); w(0x31C + s, 0x4A); w(0x584 + s, 3); w(0x46C + s, 0x80); w(0x488 + s, 0x10); w(0x338 + s, 0); w(0x38C + s, r(0x38C)); w(0x354 + s, r(0x354)); w(0x300 + s, 0) end, every = 6, len = 72},
  {name = "potion", set = function() local s = 10; w(0x434 + s, 0x2F); w(0x31C + s, 0x4A); w(0x584 + s, 0x0E); w(0x46C + s, 0x80); w(0x488 + s, 0x10); w(0x338 + s, 0); w(0x38C + s, r(0x38C)); w(0x354 + s, r(0x354)); w(0x300 + s, 0) end, every = 40, len = 480},
}
local i, t0, phase = 1, 0, "load"
local function start() loadstate_raw("castle", function() phase = "run"; t0 = F end) end
start()
FRAME = function(f)
  if phase ~= "run" then return end
  local q = SEQS[i]
  local dt = f - t0
  if dt == 5 then q.set() end
  if dt >= 5 and (dt - 5) % q.every == 0 then shot(string.format("%s_%03d", q.name, (dt - 5) // q.every)) end
  if dt - 5 > q.len then
    i = i + 1
    if i > #SEQS then log("PASS"); done(); return end
    phase = "load"; start()
  end
end
