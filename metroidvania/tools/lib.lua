M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function r16(a) return r(a) + 256 * r(a + 1) end
function w(a, v) emu.write(a, v % 256, emu.memType.nesDebug) end
function s8(v) if v >= 128 then return v - 256 end return v end
local LOG = io.open(OUT .. NAME .. ".log", "w")
function log(s) LOG:write(s .. "\n"); LOG:flush() end
function shot(tag)
  local h = io.open(OUT .. NAME .. "_" .. tag .. ".png", "wb")
  h:write(emu.takeScreenshot()); h:close()
end
function stop() LOG:close(); emu.stop(0) end
function pad(s)
  local t = {}
  for k in (s or ""):gmatch("%S+") do
    t[({A = "a", B = "b", L = "left", R = "right", U = "up", D = "down", S = "start", E = "select"})[k]] = true
  end
  return t
end
function hex(a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02x", r(a + i)) end
  return table.concat(t, " ")
end
F = 0
INPUT = function(f) return {} end
FRAME = function(f) end
emu.addEventCallback(function() emu.setInput(INPUT(F + 1), 0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  F = F + 1
  local ok, err = pcall(FRAME, F)
  if not ok then log("error: " .. tostring(err)); stop() end
end, emu.eventType.endFrame)

-- Savestates must be made and loaded from inside a CPU callback.
local function onExec(fn)
  local id
  id = emu.addMemoryCallback(function()
    emu.removeMemoryCallback(id, emu.callbackType.exec, 0x8000, 0xFFFF)
    fn()
  end, emu.callbackType.exec, 0x8000, 0xFFFF)
end
function savestate(name)
  onExec(function()
    local h = io.open(OUT .. name .. ".mss", "wb"); h:write(emu.createSavestate()); h:close()
  end)
end
function loadstate(name, fn)
  onExec(function()
    local h = io.open(OUT .. name .. ".mss", "rb"); local d = h:read("a"); h:close()
    emu.loadSavestate(d)
    if fn then fn() end
  end)
end
