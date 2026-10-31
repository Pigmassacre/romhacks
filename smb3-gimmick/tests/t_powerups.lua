-- Power-ups touched: a mushroom heals one, and a flower, leaf or suit raises the maximum and fills
-- health, up to 6 (Yumetaro being small, flowers and leaves once only counted as mushrooms).
-- ? blocks give a mushroom when he's hurt, otherwise the flower or leaf they hold (always a mushroom, once).
local CASES = {
  {"mushroom hurt",   0x0D, 2, 3, 3, 3},
  {"mushroom full",   0x0D, 3, 3, 3, 3},
  {"flower",          0x19, 2, 3, 4, 4},
  {"leaf",            0x1E, 2, 3, 4, 4},
  {"flower at cap",   0x19, 2, 6, 6, 6},
  {"block flower hurt", "block", 2, 3, 2, 3, 0x60, 0x0D},
  {"block flower full", "block", 3, 3, 3, 3, 0x60, 0x19},
  {"block leaf hurt", "block", 2, 3, 2, 3, 0x61, 0x0D},
  {"block leaf full", "block", 3, 3, 3, 3, 0x61, 0x1E},
}
local i, phase = 1, "go"
local function start()
  phase = "wait"
  onexec(function()
    local h = io.open(OUT .. "lv_W101L.mss", "rb"); local d = h:read("a"); h:close()
    emu.loadSavestate(d); F = 0; phase = "go"
  end)
end
start()
INPUT = function(f)
  local c = CASES[i]
  if phase == "go" and c[2] == "block" and f >= 8 and f < 40 then return {a = true} end
  return {}
end
local spawned
FRAME = function(f)
  if phase ~= "go" then return end
  local c = CASES[i]
  if f == 2 then
    ws("Gim_Health", c[3]); ws("Gim_MaxHealth", c[4])
    if c[2] == "block" then
      -- a ? block over his head, as he stands on 1-1's floor
      local a = 0x6000 + (px() // 256) * 0x1B0 + ((py() - 8) // 16) * 16 + (px() + 8) // 16
      w(a, c[7])
    else
      local x = px() + 4
      ws("Level_ObjectID", c[2], 4); ws("Objects_State", 2, 4); ws("Objects_X", x, 4); ws("Objects_XHi", x // 256, 4)
      ws("Objects_Y", py() + 16, 4); ws("Objects_YHi", (py() + 16) // 256, 4); ws("Objects_SpawnIdx", 0xFF, 4); ws("Objects_Var1", 0, 4)
    end
    spawned = nil
  end
  if c[2] == "block" then
    for s = 0, 7 do
      local id = rs("Level_ObjectID", s)
      if rs("Objects_State", s) ~= 0 and (id == 0x0D or id == 0x19 or id == 0x1E) then spawned = id end
    end
  end
  if f == 90 then
    if c[2] == "block" then check(spawned == c[8], string.format("%s: gave %02x", c[1], spawned or 0))
    else
      check(rs("Gim_Health") == c[5] and rs("Gim_MaxHealth") == c[6], string.format("%s: health %d of %d", c[1], rs("Gim_Health"), rs("Gim_MaxHealth")))
      check(rs("Player_Suit") == 0, c[1] .. ": no suit")
    end
    i = i + 1
    if i > #CASES then done() else start() end
  end
end
