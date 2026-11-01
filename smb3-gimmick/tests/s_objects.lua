-- Every object ID, spawned beside Yumetaro: hit by a thrown star, then dropped on from above.
-- Logs what became of it, and watches for runaway code. For looking over, not passing.
--   OBJ_FROM=n, OBJ_TO=n  the IDs, OBJ_LEVEL=name  the level to try them in
local from = tonumber(os.getenv("OBJ_FROM") or "1")
local to = tonumber(os.getenv("OBJ_TO") or "0xBC")
local LEVEL = os.getenv("OBJ_LEVEL") or "W101L"
local SLOT = 4
local id, mode = from, "star"
local base, phase, t = nil, "load", 0
local minhp, ride, killed, states
emu.addMemoryCallback(function(a) log(string.format("!! running from RAM: pc %04x id %02x %s", a, id, mode)) end, emu.callbackType.exec, 0x0000, 0x5FFF)
local names = {}
for line in io.lines(FNS) do local n, v = line:match("^(OBJ_%S+)%s+=%s+%$(%x+)"); if n then names[tonumber(v, 16)] = n end end
local function nextcase()
  if mode == "star" then mode = "stand" else mode = "star"; id = id + 1 end
  if id > to then done(); return end
  phase = "load"
  onexec(function()
    emu.loadSavestate(base); F = 0; phase = "run"; t = 0; minhp = 99; ride = 0; killed = false; states = ""
  end)
end
onexec(function()
  local h = io.open(OUT .. "lv_" .. LEVEL .. ".mss", "rb"); local d = h:read("a"); h:close()
  emu.loadSavestate(d); base = emu.createSavestate(); F = 0; phase = "run"; t = 0; minhp = 99; ride = 0; killed = false; states = ""
end)
INPUT = function(f)
  if phase ~= "run" then return {} end
  if mode == "star" then if t >= 2 and t < 40 then return {b = true} end end
  return {}
end
local lastc, stuck = 0, 0
FRAME = function(f)
  if phase ~= "run" then return end
  t = t + 1
  if t == 1 then
    local gy = py()
    local x = px() + (mode == "star" and 72 or 8)
    ws("Level_ObjectID", id, SLOT); ws("Objects_State", 1, SLOT)
    ws("Objects_X", x, SLOT); ws("Objects_XHi", x // 256, SLOT)
    ws("Objects_Y", gy + 16, SLOT); ws("Objects_YHi", (gy + 16) // 256, SLOT)
    ws("Objects_SpawnIdx", 0xFF, SLOT)
    if mode == "stand" then sety(gy - 40); ws("Player_InAir", 1) end
  end
  local st = rs("Objects_State", SLOT)
  local c = string.format("%d", st)
  if states:sub(-#c - 1) ~= "," .. c then states = states .. "," .. c end
  if rs("Gim_Health") < minhp then minhp = rs("Gim_Health") end
  if rs("Gim_RideSlot") ~= 0 then ride = ride + 1 end
  if st == 6 then killed = true end
  if rs("Counter_1") == lastc then stuck = stuck + 1 else stuck = 0 end
  lastc = rs("Counter_1")
  if t == 70 then shot(string.format("%02x_%s", id, mode)) end
  if t == 140 or stuck > 60 then
    log(string.format("%02x %-28s %-5s states %-16s id now %02x hp %d minhp %d ride %d star %02x die %d exit %d y %d stuck %d suit %d", id, names[id] or "?", mode, states, rs("Level_ObjectID", SLOT), rs("Gim_Health"), minhp, ride, rs("Star_State"), rs("Player_IsDying"), rs("Level_ExitToMap"), py(), stuck, rs("Player_Suit")))
    phase = "next"
    onexec(nextcase)
  end
end
