-- Makes the savestates the tests start from: "map" on the world map, standing on 1-1 with
-- A about to go in, and "lv_<name>" just inside every area in out/levels.txt.
local LV = levels()
local i, phase, enterAt, seen = 0, "boot", 0, 0
local boot = {}
INPUT = function(f)
  if phase == "boot" then
    if f >= 120 and f < 125 then return {start = true} end
    if f >= 200 and f < 205 then return {start = true} end
    if f >= 700 and f < 760 and f % 40 < 4 then return {right = true} end
    if f >= 800 and f < 900 and f % 40 < 4 then return {up = true} end
    return {}
  end
  if phase == "enter" and f % 8 < 3 then return {a = true} end
  return {}
end
local function nextLevel()
  i = i + 1
  if i > #LV then done() return end
  local l = LV[i]
  phase = "wait"
  onexec(function()
    local h = io.open(OUT .. "map.mss", "rb"); local d = h:read("a"); h:close()
    emu.loadSavestate(d)
    F = 0
    warp_to(l)
    phase = "enter"; seen = 0
  end)
end
FRAME = function(f)
  if phase == "boot" then
    if f == 960 then shot("map"); savestate("map"); end
    if f == 965 then nextLevel() end
  elseif phase == "enter" then
    if rs("Player_XStart") ~= 0 or rs("Level_Tileset") == 7 then seen = seen + 1 end
    if seen == 45 then
      local l = LV[i]
      savestate("lv_" .. l.name)
      shot("lv_" .. l.name)
      log(string.format("%-20s world %d tileset %2d: x %d y %d vert %d water %d hp %d mode %d", l.name, l.world, l.tileset, px(), py(), rs("Level_7Vertical"), rs("Player_InWater"), rs("Gim_Health"), rs("Level_ExitToMap")))
      phase = "saved"; enterAt = f
    end
    if f > 900 then log("FAIL never entered " .. LV[i].name); FAILS = FAILS + 1; nextLevel() end
  elseif phase == "saved" and f >= enterAt + 1 then
    nextLevel()
  end
end
