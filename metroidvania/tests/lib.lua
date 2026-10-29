-- Shared helpers for the Mesen test scripts. Run a test with tests/run.py.
-- tests/run.py defines REPO, OUT and NAME above this file.
M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function w(a, v) emu.write(a, v % 256, emu.memType.nesDebug) end
function s8(v) if v >= 128 then return v - 256 end return v end

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
-- Start from a savestate made by tests/states.lua (out/test/<name>.mss).
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
