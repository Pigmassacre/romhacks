-- In Kuribo's shoe Yumetaro is drawn standing in it (Mario's shoe frames being gone, he once hopped
-- about with no shoe), and throws no stars. A hit knocks the shoe off and leaves his health be.
local has = function(t) local so = rs("Player_SprOff"); for i = 0, 5 do if r(0x201 + so + i * 4) == t and r(0x200 + so + i * 4) < 0xF0 then return true end end return false end
loadstate_raw("lv_W503L")
INPUT = function(f) if f > 10 and f < 60 then return pad("B") end return {} end
FRAME = function(f)
  if f == 2 then ws("Player_QueueSuit", 0x80) end
  if f == 40 then
    check(rs("Player_Kuribo") ~= 0, "in the shoe")
    check(has(0xA9) and has(0xAB), "the shoe is drawn")
    check(rs("Star_State") == 0, "no star charging")
    shot("shoe")
    local hp = rs("Gim_Health")
    local x = px() + 8
    ws("Level_ObjectID", 0x29, 4); ws("Objects_State", 1, 4); ws("Objects_X", x, 4); ws("Objects_XHi", x // 256, 4)
    ws("Objects_Y", py() + 16, 4); ws("Objects_YHi", (py() + 16) // 256, 4); ws("Objects_SpawnIdx", 0xFF, 4)
  end
  if f == 90 then
    check(rs("Player_Kuribo") == 0, "the hit knocked it off")
    check(rs("Gim_Health") == 3, "with his health as it was: " .. rs("Gim_Health"))
    check(not has(0xA9), "and it isn't drawn on him")
    done()
  end
end
