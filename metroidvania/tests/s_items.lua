-- Not a test: gives Samus every item Castlevania has, on stage 1, one at a time,
-- from the castle savestate. Logs what each changes, and that she goes on.
local WATCH = {[0x71]="hearts",[0x70]="whip",[0x64]="shots",[0x15B]="sub",[0x2A]="lives",[0x118]="enHi",[0x117]="enLo",[0x5B]="inv",[0x7E]="flash",[0x7FC]="s0",[0x7FD]="s1",[0x7FE]="s2",[0x45]="hp",[0x42]="tLo",[0x43]="tHi",[0x1F]="off",[0x60]="60",[0x141]="141",[0x4A]="4a", [0x18]="mode"}
local id = tonumber(os.getenv("ITEM_FROM") or "0")
local last = 0x20
local phase, t0, base, pick = "load", 0, nil, nil
local function x() return r(0x122) + 256 * r(0x123) end
local function snap() local t = {}; for a in pairs(WATCH) do t[a] = r(a) end; return t end
local function start()
  loadstate_raw("castle", function() phase = "set"; t0 = F end)
end
start()
INPUT = function(f)
  if phase == "after" then return (f - t0) % 40 < 20 and pad("R") or pad("L A") end
  return {}
end
FRAME = function(f)
  for i = 4, 0x13 do if r(0x434 + i) == 0x01 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  if phase == "set" and f >= 5 then
    w(0x71, 10); w(0x118, 5); w(0x117, 0)
    base = snap()
    local s = 10
    w(0x434 + s, 0x2F); w(0x31C + s, 0x4A); w(0x584 + s, id); w(0x46C + s, 0x80); w(0x488 + s, 0x10); w(0x338 + s, 0)
    w(0x38C + s, r(0x38C)); w(0x354 + s, r(0x354)); w(0x300 + s, 0)
    phase = "wait"; t0 = f; pick = nil
  end
  if phase == "wait" and f == t0 + 60 then
    local d = {}
    local now = snap()
    for a, n in pairs(WATCH) do if now[a] ~= base[a] and n ~= "tLo" then d[#d + 1] = string.format("%s %02x>%02x", n, base[a], now[a]) end end
    table.sort(d)
    log(string.format("id %02x: slot ai %02x pose %02x | %s", id, r(0x434 + 10), r(0x31C + 10), table.concat(d, " ")))
    shot(string.format("%02x", id))
    phase = "after"; t0 = f; pick = x()
  end
  if phase == "after" and f == t0 + 100 then
    local moved = x() ~= pick
    local sp = 0
    for i = 17, 63 do if emu.read(i * 4, emu.memType.nesSpriteRam) < 0xEF then sp = sp + 1 end end
    log(string.format("   then: moved %s, x %04x y %02x mode %02x/%02x status %02x sprites %d", tostring(moved), x(), r(0x124), r(0x18), r(0x19), r(0x100), sp))
    id = id + 1
    if id > last then log("PASS"); done(); return end
    phase = "load"; start()
  end
end
