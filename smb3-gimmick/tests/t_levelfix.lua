-- 6-7's end: the wall that was too tall for him is steps now, and he can get over it to the card.
loadstate_raw("lv_W607_EndL")
local hops = {20, 80, 140}
INPUT = function(f)
  local t = {right = true}
  for _, h in ipairs(hops) do if f >= h and f < h + 30 then t.a = true end end
  return t
end
local best = 0
FRAME = function(f)
  ws("Gim_Health", 3)
  if px() > best then best = px() end
  if f == 300 then check(best > 170, "past the wall, to x " .. best); done() end
end
