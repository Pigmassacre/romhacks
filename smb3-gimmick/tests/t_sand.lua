-- 2-Sun's quicksand: he sinks if he does nothing, and pressing A keeps him up and gets him across.
local x0 = 39 * 16
loadstate_raw("lv_W2STL")
local phase = "cross"
INPUT = function(f)
  if f < 40 then return {} end
  local t = {right = true}
  t.a = f % 4 < 2
  return t
end
FRAME = function(f)
  if f < 40 then setx(x0); sety(350); ws("Horz_Scroll", (x0 - 100) % 256); ws("Horz_Scroll_Hi", (x0 - 100) // 256); ws("Player_YVel", 0) end
  ws("Gim_Health", 3)
  if f % 30 == 0 then log(string.format("f %d x %d y %d yv %d air %d sink %d die %d", f, px(), py(), s8(rs("Player_YVel")), rs("Player_InAir"), rs("Player_SandSink"), rs("Player_IsDying"))) end
  if rs("Player_IsDying") ~= 0 then check(false, "sank at x " .. px()); done() end
  if px() > 48 * 16 then check(true, "across at f " .. f); done() end
  if f == 2000 then check(false, "stuck at x " .. px()); done() end
end
