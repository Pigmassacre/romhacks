-- Through a pipe into another area: health stays what it was (level starts refill it), and any
-- star is gone.
loadstate_raw("lv_W101L")
local phase = "go"
FRAME = function(f)
  if f == 3 then ws("Gim_Health", 2); ws("Gim_MaxHealth", 5); ws("Star_State", 1); ws("Star_X", px() + 20); ws("Star_Y", py()); ws("Star_YHi", rs("Player_YHi")); ws("Star_XHi", 0); ws("Level_JctCtl", 1) end
  if f == 200 then
    check(rs("Gim_Health") == 2, "health still 2: " .. rs("Gim_Health"))
    check(rs("Star_State") ~= 1, "no star: " .. rs("Star_State"))
    check(rs("Level_JctCtl") == 0, "came out")
    shot("after")
    done()
  end
end
