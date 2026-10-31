-- Writes each area's tiles to out/test/map_<name>.txt, for planning routes: # solid, = solid from
-- above only, . air, and the level's objects listed. MAP_LEVELS=a,b,c picks areas.
local names = {}
for n in (os.getenv("MAP_LEVELS") or ""):gmatch("[^,]+") do names[#names + 1] = n end
if #names == 0 then for _, l in ipairs(levels()) do names[#names + 1] = l.name end end
local i = 0
local function nextone()
  i = i + 1
  if i > #names then done(); return end
  local h = io.open(OUT .. "lv_" .. names[i] .. ".mss", "rb")
  if not h then nextone(); return end
  local d = h:read("a"); h:close()
  emu.loadSavestate(d)
  local o = io.open(OUT .. "map_" .. names[i] .. ".txt", "w")
  local top, all = {}, {}
  for q = 0, 3 do top[q] = r(S["Tile_AttrTable"] + q); all[q] = r(S["Tile_AttrTable"] + 4 + q) end
  local width = rs("Level_Width")
  o:write(string.format("%s width %d vert %d start %d,%d\n", names[i], width, rs("Level_7Vertical"), px(), py()))
  for row = 0, 26 do
    local s = {}
    for sc = 0, width do
      for col = 0, 15 do
        local t = r(0x6000 + sc * 0x1B0 + row * 16 + col)
        local q = t >> 6
        s[#s + 1] = t >= all[q] and "#" or t >= top[q] and "=" or "."
      end
    end
    o:write(string.format("%2d ", row) .. table.concat(s) .. "\n")
  end
  o:close()
  F = 0
  onexec(nextone)
end
onexec(nextone)
