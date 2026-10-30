-- A whip upgrade stops the game a moment while Simon flashes. Samus has to
-- flash too: she once just froze, which looks like a hang.
local SP = emu.memType.nesSpriteRam
local seen = {}
local function samusAttrs()
  -- Samus's sprites: from the sprites around her, by their x and y
  local sx, sy = r(0x38C), r(0x124)
  for i = 17, 63 do
    local y, x = emu.read(i * 4, SP), emu.read(i * 4 + 3, SP)
    if y < 0xF0 and math.abs(x - sx) < 16 and math.abs(y - sy) < 24 then
      seen[emu.read(i * 4 + 2, SP) & 3] = true
    end
  end
end
loadstate_raw("castle", function() end)
FRAME = function(f)
  for i = 4, 0x13 do if r(0x434 + i) == 0x01 then w(0x434 + i, 0); w(0x31C + i, 0) end end
  if f == 5 then w(0x7E, 0x18) end
  if f > 6 and f < 50 then samusAttrs() end
  if f == 50 then
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    check(n >= 3, string.format("she goes through the palettes (%d)", n))
  end
  if f == 70 then
    seen = {}
    samusAttrs()
    check(seen[0] and not seen[1] and not seen[2] and not seen[3], "and back to her own")
    done()
  end
end
