-- World 1 fortress's spike room scrolls up and down over a fixed floor. A star thrown there lands
-- on the floor the screen shows, as he does (it once fell by the scrolled level's rows, and sank
-- into the floor, or through it: issue 12 of the old repository).
loadstate_raw("lv_W10F_AltL")
local deepest, thrown = 0, false
INPUT = function(f) if f >= 30 and f < 66 then return pad("B L") end return {} end
FRAME = function(f)
  ws("Gim_Health", 3)
  if f == 2 then setx(440); sety(368); ws("Horz_Scroll", 320 % 256); ws("Horz_Scroll_Hi", 1); ws("Player_YVel", 0) end
  if rs("Star_State") == 1 then
    thrown = true
    local rel = rs("Star_YHi") * 256 + rs("Star_Y") - rs("Level_VertScroll")
    if rel > deepest then deepest = rel end
  end
  if f == 95 then shot("rolling") end
  if f == 96 then
    check(thrown, "thrown")
    check(deepest <= 145, "stays on the floor at screen line 144: " .. deepest)
    done()
  end
end
