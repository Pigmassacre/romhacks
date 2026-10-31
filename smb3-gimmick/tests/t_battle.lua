-- A hammer bro battle: stars kill the bro, the treasure box comes down, and walking to it gets
-- back to the map with the panel cleared. (The box holds what the map object carried, and a warp
-- has none.)
loadstate_raw("lv_W1HBA")
local box, won = nil, false
INPUT = function(f)
  if not box then
    if f % 70 < 36 then return pad(f < 300 and "B R" or "B") end
    return {}
  end
  if px() > box + 4 then return pad("L") end
  return {}
end
FRAME = function(f)
  ws("Gim_Health", 3)
  if rs("Level_ObjectID", 0) == 0x52 and not box then box = rs("Objects_XHi", 0) * 256 + rs("Objects_X", 0); log("the box at " .. box) end
  if rs("Level_ExitToMap") ~= 0 or rs("Level_Tileset") == 0 then
    check(rs("Map_ReturnStatus") == 0, "back at the map, panel cleared")
    done()
  end
  if f == 3000 then check(false, string.format("still at %d, box %s", px(), tostring(box))); done() end
end
