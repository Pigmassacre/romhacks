-- A goomba carries Yumetaro left along 1-1's floor, to the edge of the screen. He stops there and
-- it walks out from under him: carried off the edge, he once counted as crushed, and died.
local SLOT = 4
loadstate_raw("lv_W101L")
FRAME = function(f)
  if f == 1 then
    local gy, x = py(), px() + 8
    ws("Level_ObjectID", 0x72, SLOT); ws("Objects_State", 1, SLOT)
    ws("Objects_X", x, SLOT); ws("Objects_XHi", x // 256, SLOT)
    ws("Objects_Y", gy + 16, SLOT); ws("Objects_YHi", (gy + 16) // 256, SLOT); ws("Objects_SpawnIdx", 0xFF, SLOT)
    sety(gy - 40); ws("Player_InAir", 1)
  end
  if f == 150 then
    check(rs("Player_IsDying") == 0, "alive")
    check(px() >= 14 and px() < 40, "stopped at the edge: x " .. px())
    done()
  end
end
