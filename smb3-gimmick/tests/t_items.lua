-- A power-up used from the inventory raises Yumetaro's maximum health and leaves him looking and
-- moving as himself: they once gave him Mario's suit moves, Mario's colours on the map, and a hit
-- in a suit healed him. Judgem's cloud works as it did.
local item, phase = 3, "open"
local function use(i)
  ws("Inventory_Items", i)
  phase = "open"; F = 0
end
loadstate_raw("map", function() use(3) end)
INPUT = function(f)
  if phase == "open" and f >= 5 and f < 8 then return {b = true} end
  if phase == "open" and f >= 60 and f < 63 then return {a = true} end
  if phase == "enter" and f % 8 < 3 then return {a = true} end
  return {}
end
FRAME = function(f)
  if phase == "open" and f == 120 then
    check(rs("Gim_MaxHealth") == 4, "a leaf raises the maximum to " .. rs("Gim_MaxHealth"))
    check(rs("World_Map_Power") == 0, "no suit for the map")
    check(rs("Inventory_Items") == 0, "the item is used")
    check(rs("Palette_Buffer", 17) == 0x0B, "his colours on the map")
    shot("map")
    phase = "enter"; F = 0
  elseif phase == "enter" and rs("Player_XStart") ~= 0 and f > 100 then
    check(rs("Player_Suit") == 0, "no suit in the level")
    check(rs("Gim_Health") == 4, "health full at the new maximum: " .. rs("Gim_Health"))
    done()
  end
  if f > 2000 then check(false, "stuck in " .. phase); done() end
end
