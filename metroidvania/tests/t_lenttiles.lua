-- The tile pairs Samus doesn't get to keep. The cross ($4A, $52, $54) and the orb
-- ($5A, $5C) are Castlevania's while she plays (they once held her frames, and a
-- dropped cross and the orb showed as scraps of her). As she dies her explosion
-- borrows those, but for $4A, and two pairs only her front view at the castle gate
-- uses; coming back from a death puts them all back.
local PRG = emu.memType.nesPrgRom
local PPU = emu.memType.nesPpuMemory
local LENT = {}
for l in io.lines(REPO .. "/out/gen/samus_chr.asm") do
  if l:match("^ExplodeTiles") then EXPLODE = true
  elseif EXPLODE then
    for t in l:gmatch("%$(%x%x)") do LENT[#LENT + 1] = tonumber(t, 16) end
    break
  end
end
local function read(t)
  local s = {}
  local base = (t & 1) == 1 and 0x1000 or 0
  for i = 0, 31 do s[#s + 1] = emu.read(base + (t & 0xFE) * 16 + i, PPU) end
  return table.concat(s, ",")
end
-- Simon's tiles are in bank 1 from $9008 on
local function cvs(t)
  for i = 0, 31 do
    if emu.read(t * 16 + i, PPU) ~= emu.read(0x4000 + 0x1008 + t * 16 + i, PRG) then return false end
  end
  return true
end
local phase, own = "start", {}
loadstate_raw("castle", function() end)
FRAME = function(f)
  if phase == "start" and f == 5 then
    for _, t in ipairs({0x4A, 0x52, 0x54, 0x5A, 0x5C}) do check(cvs(t), string.format("in play: pair %02x is Castlevania's", t)) end
    for _, t in ipairs(LENT) do own[t] = read(t) end
    w(0x118, 0); w(0x117, 0x10); w(0x45, 0)
    phase = "die"
  end
  if phase == "die" and r(0x46C) == 8 and r(0x100) == 8 then
    local diff = 0
    for _, t in ipairs(LENT) do if read(t) ~= own[t] then diff = diff + 1 end end
    if diff == #LENT then
      check(cvs(0x4A), "dying: the cross keeps its pair")
      check(true, "dying: the explosion's tiles went in")
      shot("explode")
      phase = "back"
    end
  end
  if phase == "back" and r(0x18) == 5 and r(0x19) == 6 and (r(0x126) & 1) == 1 and r(0x118) == 9 then
    for _, t in ipairs(LENT) do check(read(t) == own[t], string.format("back in the stage: pair %02x is back", t)) end
    done()
  end
  if f > 3000 then check(false, "stuck in " .. phase); done() end
end
