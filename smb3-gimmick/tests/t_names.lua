-- No Mario left where it shows: the world's intro box and Game Over box say YUMETARO with his sprite
-- and horn, the status bar shows <Y>, the map his horn, and the title AI SLOP, DO NOT PLAY.
local vr = function(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function row(a, n) local t = {}; for i = 0, n - 1 do t[#t + 1] = string.format("%02x", vr(a + i)) end; return table.concat(t, " ") end
local YUME = "cc da ba e8 ea bc e9 f0"
INPUT = function(f) if f >= 2000 and f < 2005 then return {start = true} end if f >= 2100 and f < 2105 then return {start = true} end return {} end
local boxed, title, t0 = false, false, nil
FRAME = function(f)
  if f == 1800 then
    check(row(0x22CC, 7) == "0c 2a 5c 2b 0b 2c 0a", "title: AI SLOP: " .. row(0x22CC, 7))
    check(row(0x22EA, 11) == "2d 2c 5c 2e 2c 2f 5c 0a 0b 0c 1a", "title: DO NOT PLAY: " .. row(0x22EA, 11))
    shot("title")
  end
  if f > 2100 and not boxed then
    local a = row(0x29A9, 8)
    if a == YUME or row(0x21A9, 8) == YUME then
      boxed = true; t0 = f
    end
  end
  if t0 and f == t0 + 30 then
    check(r(0x285) == 0x2D and r(0x289) == 0x2F and r(0x28D) == 0x49, "intro box: his body and horn")
    shot("box")
  end
  if t0 and f == t0 + 500 then
    check(boxed, "intro box: YUMETARO")
    done()
  end
  if f == 4000 then check(false, "no intro box"); done() end
end
