-- The second player is the Ohagi: black in a bright level, drawn from its own pages and with Yumetaro's star, and
-- named with its sprite in the Game Over box.
local pal = function(i) return emu.read(i, emu.memType.nesPaletteRam) end
local vr = function(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function row(a, n) local t = {}; for i = 0, n - 1 do t[#t + 1] = string.format("%02x", vr(a + i)) end; return table.concat(t, " ") end
local L
for _, l in ipairs(levels()) do if l.name == "W101L" then L = l end end
local phase, t0 = "enter", nil
loadstate_raw("map", function()
  ws("Total_Players", 1); ws("Player_Current", 1); warp_to(L); ws("Player_Lives", 0, 1)
  for _, n in ipairs({"World_Map_Y", "World_Map_XHi", "World_Map_X", "Map_Entered_Y", "Map_Entered_XHi", "Map_Entered_X"}) do ws(n, rs(n), 1) end
end)
INPUT = function(f) if phase == "enter" and f % 8 < 3 then return {a = true} end return {} end
FRAME = function(f)
  if phase == "enter" and f > 10 and rs("Player_XStart") ~= 0 then phase = "level"; t0 = f end
  if phase == "level" and f == t0 + 45 then
    check(pal(17) == 0x0F and pal(18) == 0x00 and pal(19) == 0x30, string.format("black in a bright level: %02x %02x %02x", pal(17), pal(18), pal(19)))
    check(rs("PatTable_BankSel", 2) == 0x40 or rs("PatTable_BankSel", 2) == 0x41, "from its pages")
    ws("Level_TimerMSD", 0); ws("Level_TimerMid", 0); ws("Level_TimerLSD", 1)
    phase = "die"
  elseif phase == "die" and rs("Level_Tileset") == 0 then
    phase = "menu"; t0 = f
  elseif phase == "menu" and f == t0 + 200 then
    local name = row(0x292A + rs("Horz_Scroll") // 8, 5)
    check(name == "f0 d3 bc eb fc", "named OHAGI: " .. name)
    check(rs("PatTable_BankSel", 2) == 0x42 and rs("PatTable_BankSel", 3) == 0x43, "its map pages")
    check(r(0x285) == 0x2D and r(0x289) == 0x2F, "its sprite")
    shot("menu")
    done()
  end
  if f > 3000 then check(false, "stuck in " .. phase); done() end
end
