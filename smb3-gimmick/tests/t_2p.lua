-- The first player is Yumetaro and the second the Ohagi, in black: on the map, in levels, in the status
-- bar's <O>, and each player's marker a Y or an O. (They were Mario and Luigi in the title and the battle,
-- and had M and L on the map.) The first dies in 1-1, and the second has their turn.
local pal = function(i) return emu.read(i, emu.memType.nesPaletteRam) end
local vr = function(a) return emu.read(a, emu.memType.nesPpuMemory) end
local phase, t = "title", 0
local function walk(g)
  if g >= 0 and g < 60 and g % 40 < 4 then return {right = true} end
  if g >= 100 and g < 200 and g % 40 < 4 then return {up = true} end
  if g >= 300 and g % 20 < 3 then return {a = true} end
  return {}
end
INPUT = function(f)
  if phase == "title" then
    if f >= 120 and f < 125 then return {start = true} end
    if f >= 160 and f < 163 then return {select = true} end
    if f >= 200 and f < 205 then return {start = true} end
    return {}
  end
  if phase == "first" or phase == "second" then return walk(f - t) end
  return {}
end
FRAME = function(f)
  if phase == "title" and f == 700 then
    check(rs("Total_Players") ~= 0, "2 players chosen")
    check(pal(17) == 0x0B and pal(18) == 0x2A, "the first's colours on the map")
    shot("first")
    phase = "first"; t = f
  elseif phase == "first" and rs("Level_Tileset") ~= 0 and rs("Player_XStart") ~= 0 then
    ws("Level_TimerMSD", 0); ws("Level_TimerMid", 0); ws("Level_TimerLSD", 1)
    phase = "dying"
  elseif phase == "dying" and rs("Level_Tileset") == 0 and rs("Player_Current") == 1 then
    phase = "turn"; t = f
  elseif phase == "turn" and f == t + 400 then
    check(pal(17) == 0x0F and pal(18) == 0x00 and pal(19) == 0x30, string.format("the Ohagi's colours on the map: %02x %02x %02x", pal(17), pal(18), pal(19)))
    check(rs("PatTable_BankSel", 2) == 0x42, "its map sprite page")
    shot("second")
    phase = "second"; t = f
  elseif phase == "second" and rs("Level_Tileset") == 18 and f > t + 500 then
    -- on the same spot as the first, they go into battle
    check(pal(17) == 0x0B and pal(21) == 0x00 and pal(22) == 0x10, string.format("in battle, both colours: %02x %02x", pal(17), pal(21)))
    local c, d = r(0x221), r(0x229)
    check(r(0x219) == 0x31, "the first with a horn")
    check(d == 0xDF or d == 0xE3 or d == 0xE5 or d == 0xF5 or d == 0xF7 or d == 0xF9 or d == 0xFB, string.format("the second's the Ohagi: %02x", d))
    shot("battle")
    phase = "wait"
    -- then a level with the second player's turn, through a pipe to load its colours
    onexec(function()
      local h = io.open(OUT .. "lv_W101L.mss", "rb"); local d = h:read("a"); h:close()
      emu.loadSavestate(d); F = 0; ws("Player_Current", 1); ws("Level_JctCtl", 1); phase = "last"
    end)
  elseif phase == "last" and f == 200 then
    -- this room is black, so it's grey here, not to vanish
    check(pal(0) == 0x0F and pal(17) == 0x00 and pal(18) == 0x10, string.format("and in a black level, the Ohagi's colours: %02x %02x", pal(17), pal(18)))
    check(rs("PatTable_BankSel", 2) == 0x40 or rs("PatTable_BankSel", 2) == 0x41, "from its pages")
    shot("level")
    done()
  end
  if f > 6000 then check(false, "stuck in " .. phase); done() end
end
