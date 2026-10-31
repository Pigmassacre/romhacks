-- The title is Castlevania's with METROID in place of CASTLE (src/title.asm, from
-- the title editor): on screen after the first load and again after the attract
-- demo, with no big C, the bat still landing, and PUSH START KEY flashing into
-- a game with the stages' own graphics.
local P, S = emu.memType.nesPpuMemory, emu.memType.nesSpriteRam
local want = tonumber(io.open(REPO .. "/src/title.asm"):read("a"):match("checksum (%d+)"))
local function screenSum()
  local n = 0
  for a = 0x2000, 0x23FF do n = n + emu.read(a, P) end
  return n
end
local function cSprites()
  local n = 0
  for i = 1, 63 do
    local y, x = emu.read(i * 4, S), emu.read(i * 4 + 3, S)
    if y < 0xEF and x >= 32 and x < 80 and y < 130 then n = n + 1 end
  end
  return n
end
local phase, t0, seenDemo, flash, last = "title", 0, false, 0, nil
INPUT = function(f)
  if phase == "start" and f == t0 + 2 then return {start = true} end
  return {}
end
FRAME = function(f)
  local mode = r(0x18)
  if phase == "title" and mode == 1 and r(0x19) == 1 then
    shot("title")
    check(screenSum() == want, string.format("the design is on screen (%d, want %d)", screenSum(), want))
    check(cSprites() == 0, string.format("no big C (%d sprites where it was)", cSprites()))
    check(emu.read(0x3F0D, P) == 6 and emu.read(0x3F0E, P) == 0x11, "the logo's palette")
    phase = "demo"
  end
  if phase == "demo" and mode == 2 then seenDemo = true end
  if phase == "demo" and seenDemo and mode == 1 and r(0x19) == 1 then
    check(screenSum() == want, "and again after the attract demo")
    check(cSprites() == 0, "still no big C")
    phase = "start"; t0 = f
  end
  if phase == "start" and mode == 3 then
    local sum = screenSum()
    if last and sum ~= last then flash = flash + 1 end
    last = sum
  end
  if phase == "start" and mode == 5 and r(0x19) == 6 then
    check(flash >= 2, string.format("PUSH START KEY flashes (%d changes)", flash))
    check(r(0x28) == 0, "the game starts at the gate")
    shot("gate")
    done()
  end
  if f > 12000 then check(false, "got through (" .. phase .. string.format(", mode %02x)", mode)); done() end
end
