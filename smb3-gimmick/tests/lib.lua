-- Shared helpers for the Mesen test scripts. Run a test with tests/run.py,
-- which defines REPO, OUT, NAME and FNS above this file.
M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function w(a, v) emu.write(a, v % 256, emu.memType.nesDebug) end
function s8(v) if v >= 128 then return v - 256 end return v end

-- Every label of the build, by name
S = {}
for line in io.lines(FNS) do
  local n, v = line:match("^(%S+)%s+=%s+%$(%x+)")
  if n then S[n] = tonumber(v, 16) end
end
function rs(name, o) return r(S[name] + (o or 0)) end
function ws(name, v, o) w(S[name] + (o or 0), v) end

local LOG = io.open(OUT .. NAME .. ".log", "w")
function log(s) LOG:write(s .. "\n"); LOG:flush() end
function shot(tag)
  local h = io.open(OUT .. NAME .. "_" .. tag .. ".png", "wb")
  h:write(emu.takeScreenshot()); h:close()
end

FAILS = 0
function check(cond, msg)
  if cond then log("ok   " .. msg) else log("FAIL " .. msg); FAILS = FAILS + 1 end
end
function done()
  log(FAILS == 0 and "PASS" or ("FAILED " .. FAILS))
  LOG:close()
  emu.stop(FAILS == 0 and 0 or 1)
end

function pad(s)
  local t = {}
  for k in (s or ""):gmatch("%S+") do
    t[({A = "a", B = "b", L = "left", R = "right", U = "up", D = "down", S = "start", E = "select"})[k]] = true
  end
  return t
end

function px() return rs("Player_XHi") * 256 + rs("Player_X") end
function py() local h = rs("Player_YHi"); if h >= 128 then h = h - 256 end; return h * 256 + rs("Player_Y") end
function setx(x) ws("Player_X", x); ws("Player_XHi", x // 256) end
function sety(y) ws("Player_Y", y); ws("Player_YHi", y // 256) end
function inlevel() return rs("Level_ExitToMap") == 0 and rs("Player_XStart") ~= 0 end

INPUT = function(f) return {} end
FRAME = function(f) end
F = 0
emu.addEventCallback(function() emu.setInput(INPUT(F + 1), 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  F = F + 1
  local ok, err = pcall(FRAME, F)
  if not ok then log("FAIL error: " .. tostring(err)); FAILS = FAILS + 1; done() end
end, emu.eventType.endFrame)

-- Savestates must be made and loaded from inside a CPU callback.
function onexec(fn)
  local id
  id = emu.addMemoryCallback(function()
    emu.removeMemoryCallback(id, emu.callbackType.exec, 0x8000, 0xFFFF)
    fn()
  end, emu.callbackType.exec, 0x8000, 0xFFFF)
end
-- Start from a savestate made by tests/s_states.lua (out/test/<name>.mss).
function loadstate_raw(name, fn)
  onexec(function()
    local h = io.open(OUT .. name .. ".mss", "rb")
    if not h then log("FAIL no savestate " .. name .. ": run tests/run.py states first"); FAILS = FAILS + 1; done() return end
    local d = h:read("a"); h:close()
    emu.loadSavestate(d)
    F = 0
    if fn then fn() end
  end)
end
function savestate(name)
  onexec(function()
    local h = io.open(OUT .. name .. ".mss", "wb"); h:write(emu.createSavestate()); h:close()
  end)
end

-- The levels of the world maps, from tools/levels.py: name, world, tileset, layout, objects.
function levels()
  local t = {}
  for line in io.lines(REPO .. "/out/levels.txt") do
    local n, a, b, c, d = line:match("^(%S+) (%d+) (%d+) (%d+) (%d+)")
    if n then t[#t + 1] = {name = n, world = tonumber(a), tileset = tonumber(b), lay = tonumber(c), obj = tonumber(d)} end
  end
  return t
end
-- As the map enters its next level, enter this one instead.
function warp_to(l)
  warp_level = l
end
emu.addMemoryCallback(function()
  local l = warp_level
  if not l then return end
  ws("World_Num", l.world); ws("Level_Tileset", l.tileset)
  ws("Level_LayPtr_AddrL", l.lay); ws("Level_LayPtr_AddrH", l.lay >> 8)
  ws("Level_LayPtrOrig_AddrL", l.lay); ws("Level_LayPtrOrig_AddrH", l.lay >> 8)
  ws("Level_ObjPtr_AddrL", l.obj); ws("Level_ObjPtr_AddrH", l.obj >> 8)
  ws("Level_ObjPtrOrig_AddrL", l.obj); ws("Level_ObjPtrOrig_AddrH", l.obj >> 8)
  -- a battle's enemy comes from the map object that was walked into
  if l.name:match("HB[A-D]$") then ws("Map_EnterViaID", 3) end
end, emu.callbackType.exec, S["PRG030_892A"], S["PRG030_892A"])
