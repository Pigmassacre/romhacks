-- Yumetaro drops onto a rolling star: he lands on it without being pulled up onto it (he once rose
-- 15 pixels in a frame), it carries him, and he jumps from it higher than he can from the floor.
loadstate_raw("lv_W103L")
local on, peak, floor_, lasty, pop, x0 = 0, 999, nil, nil, 0, nil
INPUT = function(f) if on >= 3 and on < 28 then return {a = true} end return {} end
FRAME = function(f)
  local y = py()
  if f == 2 then
    floor_ = y
    ws("Star_State", 1); ws("Star_X", px()); ws("Star_XHi", rs("Player_XHi")); ws("Star_Y", y + 16); ws("Star_YHi", (y + 16) // 256)
    ws("Star_XVel", 16); ws("Star_YVel", 0); ws("Star_Standable", 1); ws("Star_StillCnt", 0); ws("Star_Floor", 1); ws("Star_Ridden", 0)
    sety(y - 18); ws("Player_InAir", 1); ws("Player_YVel", 0)
    lasty = nil
    return
  end
  if f < 3 then return end
  if lasty and rs("Star_Ridden") ~= 0 and on == 0 then pop = lasty - y; x0 = px() end
  if on == 2 then check(px() > x0, "carried along") end
  lasty = y
  if rs("Star_Ridden") ~= 0 or on > 0 then on = on + 1 end
  if on > 3 and y < peak then peak = y end
  if on == 60 or f == 300 then
    check(on > 0, "got on the star")
    check(pop <= 8, "landed without being pulled up: " .. pop)
    check(floor_ - peak > 60, "jumped from it higher than from the floor: " .. (floor_ - peak))
    done()
  end
end
