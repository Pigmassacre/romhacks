-- Out of lives: the Game Over menu comes up, and Start on Continue gives 4 lives, with the maximum
-- health back at 3 and for that player only (it was once one maximum for both players).
local phase = "die"
loadstate_raw("lv_W101L", function() ws("Player_Lives", 0); ws("Gim_MaxHealth", 6); ws("Gim_MaxHealth", 5, 1) end)
INPUT = function(f)
  if phase == "menu" then
    if f % 60 < 3 then return {start = true} end
    return {}
  end
  return {}
end
local t0
FRAME = function(f)
  if phase == "die" then
    if f == 3 then ws("Level_TimerMSD", 0); ws("Level_TimerMid", 0); ws("Level_TimerLSD", 1) end
    if rs("Level_Tileset") == 0 and f > 30 then phase = "menu"; t0 = f; shot("over") end
    if f > 1500 then check(false, "never left the level"); done() end
    return
  end
  if phase == "menu" then
    if f == t0 + 150 then
      shot("menu")
      local t = {}
      for i = 0, 8 do t[#t + 1] = string.format("%02x", r(0x285 + i * 4)) end
      check(r(0x285) == 0x2D and r(0x289) == 0x2F and r(0x28D) == 0x49, "his sprite and horn, not Mario: " .. table.concat(t, " "))
    end
    if rs("Player_Lives") >= 3 and rs("Player_Lives") < 0x80 then
      check(rs("Gim_MaxHealth") == 3, "Mario's maximum back at 3: " .. rs("Gim_MaxHealth"))
      check(rs("Gim_MaxHealth", 1) == 5, "Luigi's left as it was: " .. rs("Gim_MaxHealth", 1))
      check(rs("Player_Lives") == 4, "4 lives: " .. rs("Player_Lives"))
      done()
    end
    if f > t0 + 2000 then check(false, "no way on from the menu, lives " .. rs("Player_Lives")); shot("stuck"); done() end
  end
end
