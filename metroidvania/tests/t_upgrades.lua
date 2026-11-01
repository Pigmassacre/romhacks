-- The axe unlocks the Screw Attack and the cross the Wave Beam, for good: through a
-- death, not a game over. (physics holds both to Metroid.) Along the hall's zombies:
-- the Wave Beam's shots hit them, and spinning through them hits them, with no damage
-- to her and no blinking. And the stack stays clear of the hack's RAM.
local PPU = emu.memType.nesPpuMemory
local UP = 0x1CD
local phase, t0 = "load", 0
local shotHits, screwHits, lastAI, hurt, en = 0, 0, {}, 0, 0
local minsp = 0x1FF
emu.addMemoryCallback(function(a) if a < minsp then minsp = a end end, emu.callbackType.write, 0x01D2, 0x01FF)
local function spawn(id)
  local s = 10
  w(0x434 + s, 0x2F); w(0x31C + s, 0x4A); w(0x584 + s, id); w(0x46C + s, 0x80); w(0x488 + s, 0x10); w(0x338 + s, 0)
  w(0x38C + s, r(0x38C)); w(0x354 + s, r(0x354)); w(0x300 + s, 0)
end
loadstate_raw("castle", function() phase = "start"; t0 = F end)
INPUT = function(f)
  if phase == "wave" then
    local t = {b = f % 12 == 0}
    if f % 200 < 120 then t.right = true end
    return t
  end
  if phase == "screw" then
    if (f - t0) % 70 < 50 then return pad("R A") end
    return pad("R")
  end
  if phase == "over" and f % 40 == 0 then return {} end
  return {}
end
local function spinning()
  return (r(0x105) == 0x0E or (r(0x105) == 0x0C and r(0x109) >= 0x80)) and r(0x100) == 1
end
FRAME = function(f)
  if phase == "start" and f == t0 + 5 then
    check(r(UP) == 0, "no upgrades to start with")
    spawn(0x0D); phase = "axe"; t0 = f
  end
  if phase == "axe" and f == t0 + 30 then
    check(r(UP) == 8, string.format("the axe unlocks the Screw Attack (%02x)", r(UP)))
    spawn(0x09); phase = "cross"; t0 = f
  end
  if phase == "cross" and f == t0 + 30 then
    check(r(UP) == 0x48, string.format("the cross unlocks the Wave Beam (%02x)", r(UP)))
    phase = "wave"; t0 = f
  end
  if phase == "wave" then
    w(0x118, 9)
    for s = 0, 2 do
      local ai = r(0x434 + 0x14 + s)
      if r(0x7CF + s) == 2 and lastAI[s] == 0x17 and ai == 0x32 then shotHits = shotHits + 1 end
      lastAI[s] = ai
    end
    if f == t0 + 40 then shot("wave") end
    if f == t0 + 900 then
      check(shotHits >= 2, string.format("wave shots hit things (%d)", shotHits))
      phase = "screw"; t0 = f; en = r(0x118) * 256 + r(0x117); lastAI = {}
    end
  end
  if phase == "screw" then
    local now = r(0x118) * 256 + r(0x117)
    if now < en and spinning() then hurt = hurt + 1 end
    en = now
    if r(0x118) < 2 then w(0x118, 9); en = r(0x118) * 256 + r(0x117) end
    for s = 0, 2 do
      local ai = r(0x434 + 0x14 + s)
      if r(0x7CF + s) == 0 and lastAI[s] == 0x17 and ai == 0x32 then screwHits = screwHits + 1 end
      lastAI[s] = ai
    end
    if f == t0 + 30 then shot("screw1") end
    if f == t0 + 33 then shot("screw2") end
    if f == t0 + 1500 then
      check(screwHits >= 1, string.format("spinning hits things (%d)", screwHits))
      check(hurt == 0, string.format("and nothing hurts her at it (%d)", hurt))
      w(0x118, 0); w(0x117, 0x10); w(0x45, 0)
      phase = "die"; t0 = f
    end
  end
  if phase == "die" and r(0x46C) == 8 then phase = "dying" end
  if phase == "dying" and r(0x18) == 5 and r(0x19) == 6 and r(0x46C) ~= 8 and (r(0x126) & 1) == 1 then
    check(r(UP) == 0x48, string.format("they last through a death (%02x)", r(UP)))
    w(0x2A, 1); w(0x118, 0); w(0x117, 0x10); w(0x45, 0)
    phase = "die2"; t0 = f
  end
  if phase == "die2" and r(0x18) == 0x0D then
    check(r(UP) == 0, string.format("but not a game over (%02x)", r(UP)))
    check(minsp > 0x1D3, string.format("the stack stays clear (lowest $%04X)", minsp))
    done()
  end
  if f > 6000 then check(false, "stuck in " .. phase); done() end
end
