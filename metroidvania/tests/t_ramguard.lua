-- The hack's RAM is RAM Castlevania never writes: run against the original
-- game (tests/run.py --rom "Castlevania I.nes" ramguard), the attract demos
-- and a long stretch of play never touch $0100-$012F, $01B2-$01CC or
-- $07CF-$07F0. Run against the hack, the stack never reaches $01CC.
local hits = {}
local function watch(lo, hi)
  emu.addMemoryCallback(function(a) if not HACK then hits[a] = (hits[a] or 0) + 1 end end, emu.callbackType.write, lo, hi)
end
watch(0x0100, 0x012F); watch(0x01B2, 0x01CC); watch(0x07CF, 0x07F0)
-- the stack's lowest write, above the hack's bytes
local minsp = 0x1FF
emu.addMemoryCallback(function(a) if a < minsp then minsp = a end end, emu.callbackType.write, 0x01CD, 0x01FF)
INPUT = function(f)
  if f < 9000 then return {} end                       -- the attract demos
  if f < 9700 then return {start = (f % 120) < 3} end
  local p = f % 150
  if p < 90 then return pad("R") end
  if p < 96 then return pad("R A") end
  if p < 120 then return pad("U B") end
  if p < 130 then return pad("D B") end
  return pad("L B")
end
FRAME = function(f)
  if f == 18000 then
    if HACK then
      check(minsp > 0x1D0, string.format("the stack stays well above $01CC (lowest $%04X)", minsp))
    else
      local n, first = 0, nil
      for a in pairs(hits) do n = n + 1; first = first or a end
      check(n == 0, n == 0 and "the hack's RAM is never written" or string.format("%d of the hack's bytes written, e.g. $%04X", n, first))
    end
    done()
  end
end
