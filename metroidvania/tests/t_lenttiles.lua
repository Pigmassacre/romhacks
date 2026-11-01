-- The tile pairs Samus doesn't get to keep: the cross ($4A, $52, $54), the orb ($5A,
-- $5C) and the title's bat ($6A) are Castlevania's until she dies; then the
-- explosion borrows all but $4A, and a stage loading gives them back (they
-- once held Samus's frames, and a dropped cross and the orb showed as scraps of her).
local PRG = emu.memType.nesPrgRom
local PPU = emu.memType.nesPpuMemory
local PAIRS = {0x4A, 0x52, 0x54, 0x5A, 0x5C, 0x6A}
local LENT = {0x6A, 0x52, 0x54, 0x5A, 0x5C}
-- Simon's tiles are in bank 1 from $9008 on
local function same(t)
  for i = 0, 31 do
    if emu.read(t * 16 + i, PPU) ~= emu.read(0x4000 + 0x1008 + t * 16 + i, PRG) then return false end
  end
  return true
end
local function allSame(tag)
  for _, t in ipairs(PAIRS) do check(same(t), string.format("%s: pair %02x is Castlevania's", tag, t)) end
end
local phase, tiles = "start", 0
loadstate_raw("castle", function() end)
FRAME = function(f)
  if phase == "start" and f == 5 then
    allSame("in play")
    w(0x118, 0); w(0x117, 0x10); w(0x45, 0)
    phase = "die"
  end
  if phase == "die" and r(0x46C) == 8 and r(0x100) == 8 and r(0x10C) ~= nil then
    local diff = 0
    for _, t in ipairs(LENT) do if not same(t) then diff = diff + 1 end end
    if diff == #LENT then
      check(same(0x4A), "dying: the cross keeps its pair")
      check(true, "dying: the explosion's tiles went in")
      shot("explode")
      phase = "back"
    end
  end
  if phase == "back" and r(0x18) == 5 and r(0x19) == 6 and (r(0x126) & 1) == 1 and r(0x118) == 9 then
    allSame("back in the stage")
    done()
  end
  if f > 3000 then check(false, "stuck in " .. phase); done() end
end
