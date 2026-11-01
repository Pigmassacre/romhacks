-- A toad house: B opens a chest beside him and out comes the item, and the game goes back to the
-- map, also with a star thrown at the item as it rises.
local cx = 60
local opened
local hit = 0
loadstate_raw("lv_TOADL")
INPUT = function(f)
  if not opened then
    if px() < cx then return pad("R") end
    opened = f + 10
    return {}
  end
  if f < opened then return {} end
  if f < opened + 38 then return pad("B") end
  if f < opened + 400 and f % 80 < 40 then return pad("B") end
  return {}
end
local item, thrown = 0, false
FRAME = function(f)
  for s = 0, 7 do
    if rs("Level_ObjectID", s) == 0x35 and rs("Objects_State", s) == 2 then
      item = item + 1
      if item == 8 and not thrown then
        -- a star comes down on it
        thrown = true
        local x, y = rs("Objects_XHi", s) * 256 + rs("Objects_X", s), rs("Objects_YHi", s) * 256 + rs("Objects_Y", s)
        ws("Star_State", 1); ws("Star_X", x); ws("Star_XHi", x // 256); ws("Star_Y", y); ws("Star_YHi", y // 256)
        ws("Star_XVel", 0); ws("Star_YVel", 8)
      end
    end
  end
  if opened and f == opened + 40 then shot("open"); log(string.format("f %d x %d y %d item frames %d star %02x", f, px(), py(), item, rs("Star_State"))) end
  if rs("Level_Tileset") == 0 or rs("Level_ExitToMap") ~= 0 then
    check(item > 0, "the item came out")
    local n = 0
    for i = 0, 27 do if rs("Inventory_Items", i) ~= 0 then n = n + 1 end end
    check(n == 1, "and is in the inventory: " .. n)
    log("back at f " .. f)
    done()
  end
  if f == 1800 then shot("stuck"); check(false, string.format("still in the house: x %d y %d item %d", px(), py(), item)); done() end
end
