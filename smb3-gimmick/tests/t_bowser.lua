-- World 8's end: stars wear Bowser down until he falls through the floor, the door appears, and it
-- leads to the princess and the end of the game, Yumetaro at her side in his own colours (it was
-- once Mario, the one place he stayed). (Bowser's 34 hits are cut to one for the test.)
local arrived, phase, n = false, "fight", 0
local TX = 3140
local function bowser() for i = 0, 4 do if rs("Level_ObjectID", i) == 0x18 and rs("Objects_State", i) ~= 0 then return i end end end
loadstate_raw("lv_W8BCL")
local fell, doorx = false, 3304
INPUT = function(f)
  if not arrived then return {} end
  if phase == "ending" then return (f % 200 < 3) and {a = true} or {} end
  local b = bowser()
  if fell then
    local d = doorx - px()
    local t = {up = true}
    if d > 1 then t.right = true elseif d < -1 then t.left = true end
    t.a = f % 40 < 24
    return t
  end
  local d = rs("Objects_XHi", b) * 256 + rs("Objects_X", b) - px()
  local c = f % 70
  if c < 4 then return d > 0 and pad("B R") or pad("B L") end
  if c < 38 then return pad("B") end
  if c > 50 and c < 64 then return pad("A") end
  return {}
end
FRAME = function(f)
  if phase == "ending" then
    if f % 400 == 0 then n = n + 1; shot(string.format("%02d", n)) end
    if f - phase2 == 700 then
      local tiles = {}
      for a = 0x210, 0x21C, 4 do tiles[#tiles + 1] = string.format("%02x", r(a + 1)) end
      check(rs("PatTable_BankSel", 2) == 0x50 and r(0x219) == 0x03 and (r(0x211) == 0x05 or r(0x211) == 0x09 or r(0x211) == 0x0D), "Yumetaro in the chamber: " .. table.concat(tiles, " "))
      check(emu.read(0x11, emu.memType.nesPaletteRam) == 0x0B, "in his colours")
    end
    if f - phase2 > 8000 then
      check(true, "the ending ran without stopping")
      done()
    end
    return
  end
  ws("Gim_Health", 3)
  if not fell then ws("Level_TimerMSD", 3) end
  if not arrived then
    local x = px() + 6
    setx(x); sety(math.max(py() - 4, 250)); ws("Player_YVel", 0); ws("Player_InAir", 1)
    if x >= TX then arrived = true end
    return
  end
  local b = bowser()
  if b and rs("Objects_HitCount", b) > 1 then ws("Objects_HitCount", 1, b) end
  if b and rs("Objects_YHi", b) >= 4 and not fell then fell = true; log("he fell at f " .. f) end
  if rs("Player_IsDying") ~= 0 then check(false, "died at " .. px() .. "," .. py()); done() end
  if rs("Player_RescuePrincess") ~= 0 then
    check(fell, "through the door at f " .. f)
    phase = "ending"; phase2 = f; shot("door")
  end
  if f == 12000 then check(false, string.format("stuck at %d,%d fell %s", px(), py(), tostring(fell))); shot("stuck"); done() end
end
