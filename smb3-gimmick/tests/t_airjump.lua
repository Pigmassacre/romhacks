-- Standing on a parabeetle, which carries Yumetaro through the air, A jumps off it: the game says
-- he may with Player_AllowAirJump, which his jump once ignored.
local SLOT = 4
loadstate_raw("lv_W506L")
local on, leapt = 0, false
INPUT = function(f) if on >= 10 and on < 26 then return {a = true} end return {} end
FRAME = function(f)
  if f == 1 then
    local x, y = px() + 8, py() - 8
    ws("Level_ObjectID", 0x9F, SLOT); ws("Objects_State", 1, SLOT)
    ws("Objects_X", x, SLOT); ws("Objects_XHi", x // 256, SLOT)
    ws("Objects_Y", y, SLOT); ws("Objects_YHi", y // 256, SLOT); ws("Objects_SpawnIdx", 0xFF, SLOT)
    sety(y - 40); ws("Player_InAir", 1)
  end
  if rs("Player_AllowAirJump") ~= 0 and on < 10 then on = on + 1 end
  if on >= 10 then
    on = on + 1
    if s8(rs("Player_YVel")) < -40 then leapt = true end
  end
  if on == 40 or f == 200 then
    check(on > 0, "stood on the parabeetle")
    check(leapt, "jumped from it")
    done()
  end
end
