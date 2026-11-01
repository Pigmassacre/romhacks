-- Writes each area's tiles to out/test/map_<name>.txt, for planning routes: # solid, = solid from
-- above only, . air, ~ water, D doors, P pipes to go into, and the level's objects. MAP_LEVELS=a,b,c picks areas.
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
  local idx = rs("Level_TilesetIdx")
  o:write(string.format("%s width %d vert %d start %d,%d\n", names[i], width, rs("Level_7Vertical"), px(), py()))
  for row = 0, 26 do
    local s = {}
    for sc = 0, width do
      for col = 0, 15 do
        local t = r(0x6000 + sc * 0x1B0 + row * 16 + col)
        local q = t >> 6
        local c = t >= all[q] and "#" or t >= top[q] and "=" or "."
        if c == "." and t >= r(S["Level_MinTileUWByQuad"] + idx * 4 + q) then c = "~" end
        if t == 0x42 or t == 0x43 then c = "D" end
        if t == 0xAD or t == 0xAF or t == 0xB3 or t == 0xBD or t == 0xB5 then c = "P" end
        s[#s + 1] = c
      end
    end
    o:write(string.format("%2d ", row) .. table.concat(s) .. "\n")
  end
  for k = 0, 47 do
    local id = rs("Level_Objects", 1 + k * 3)
    if id == 0xFF then break end
    o:write(string.format("obj %02x %d %d\n", id, rs("Level_Objects", 2 + k * 3), rs("Level_Objects", 3 + k * 3)))
  end
  o:close()
  F = 0
  onexec(nextone)
end
onexec(nextone)
