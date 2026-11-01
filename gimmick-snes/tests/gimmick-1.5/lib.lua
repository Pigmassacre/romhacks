-- Shared helpers for the Mesen test scripts. Run a test with tests/run.py.
--
-- A test sets INPUT(f) (buttons for game frame f) and FRAME(f) (checks after
-- frame f). Frame 1 is the first frame of stage 1 with Yumetaro in control.

-- tests/run.py defines REPO and NAME above this file.
OUT = REPO .. "/out/test/"
M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function w(a, v) emu.write(a, v % 256, emu.memType.nesDebug) end
function s8(v) if v >= 128 then return v - 256 end return v end

-- Symbols from src/defs.asm (NAME = $XXXX)
SYM = {}
for line in io.lines(REPO .. "/src/gimmick-1.5/defs.asm") do
  local n, v = line:match("^(%S+)%s*=%s*%$(%x+)")
  if n then SYM[n] = tonumber(v, 16) else
    n, v = line:match("^(%S+)%s*=%s*(%d+)")
    if n then SYM[n] = tonumber(v) end
  end
end
function rs(name, o) return r(SYM[name] + (o or 0)) end

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

-- Yumetaro and star state, for logs
function state()
  return string.format("p=%02x x=%02x.%02x y=%02x.%02x vx=%4d vy=%4d fl=%02x | s=%02x x=%02x.%02x y=%02x.%02x vx=%4d vy=%4d st=%02x | g=%02x %02x.%02x %02x.%02x",
    r(0x90), r(0xB8), r(0xAE), r(0xA4), r(0x9A), s8(r(0xCC)), s8(r(0xC2)), r(0x36E),
    r(0x91), r(0xB9), r(0xAF), r(0xA5), r(0x9B), s8(r(0xCD)), s8(r(0xC3)), r(0xD7),
    rs("FX_T"), rs("FX_XTile"), rs("FX_XSub"), rs("FX_YTile"), rs("FX_YSub"))
end

-- Buttons: a string like "R B" or a table
function pad(s)
  local t = {}
  for k in (s or ""):gmatch("%S+") do
    local m = ({A = "a", B = "b", L = "left", R = "right", U = "up", D = "down", S = "start", E = "select"})[k]
    t[m] = true
  end
  return t
end

INPUT = function(f) return {} end
FRAME = function(f) end
BOOT_MAX = 1500

-- Boot: press Start until the stage is playable, then hand over to the test.
local raw = 0      -- frames since power-on
local game = nil   -- frames since Yumetaro got control
emu.addEventCallback(function()
  local inp = {}
  if game == nil then
    if r(0x90) == 0 and not NO_BOOT then inp = {start = (raw % 60) < 5} end
  else
    inp = INPUT(game + 1)
  end
  emu.setInput(inp, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  raw = raw + 1
  if game == nil then
    -- Stage 1 is playable once Yumetaro's status is 1 for a while.
    if r(0x90) == 1 and raw > 600 then game = 0 end
    if raw > BOOT_MAX then log("FAIL boot"); FAILS = FAILS + 1; done() end
    return
  end
  game = game + 1
  local ok, err = pcall(FRAME, game)
  if not ok then log("FAIL error: " .. tostring(err)); FAILS = FAILS + 1; done() end
end, emu.eventType.endFrame)

-- ---- Map editing --------------------------------------------------------
-- The level map is in cartridge RAM. Column pointers come from fixed-bank
-- tables, the same way the game's own tile probes find them ($80F6).
function mapaddr(xt, yt)
  local lo = r(0xF0BC + xt)
  local hi = (r(0xF13C + xt) + r(0xF66C + (yt >> 4))) % 256
  return hi * 256 + lo + (yt % 16)
end
function tile(xt, yt) return r(mapaddr(xt, yt)) end
function settile(xt, yt, t) w(mapaddr(xt, yt), t) end
function solid(t) return r(0x7E00 + t) >= 0x80 end

-- ---- Scenarios ----------------------------------------------------------
-- SCENARIOS = { {name=, len=, input=function(f), frame=function(f)}, ... }
-- Each one starts from the same savestate, taken on game frame 1.
local function onExec(fn)
  local id
  id = emu.addMemoryCallback(function()
    emu.removeMemoryCallback(id, emu.callbackType.exec, 0x8000, 0xFFFF)
    fn()
  end, emu.callbackType.exec, 0x8000, 0xFFFF)
end
local START, si, sf = nil, 0, 0
local loading = false
function run_scenarios()
  INPUT = function(f)
    local sc = SCENARIOS[si]
    if loading or not sc then return {} end
    return sc.input and sc.input(sf + 1) or {}
  end
  FRAME = function(f)
    if loading then return end
    if f == 1 then
      si, sf = 1, 0
      loading = true
      onExec(function()
        START = emu.createSavestate()
        loading = false
        log("== " .. SCENARIOS[1].name)
        if SCENARIOS[1].setup then SCENARIOS[1].setup() end
      end)
      return
    end
    local sc = SCENARIOS[si]
    sf = sf + 1
    if sc.frame then sc.frame(sf) end
    if sf >= sc.len then
      si = si + 1
      if si > #SCENARIOS then done() return end
      loading = true
      onExec(function()
        emu.loadSavestate(START)
        sf = 0
        loading = false
        log("== " .. SCENARIOS[si].name)
        if SCENARIOS[si].setup then SCENARIOS[si].setup() end
      end)
    end
  end
end

-- ---- Warping --------------------------------------------------------------
-- Go to a stage by setting it and dying: the respawn loads stage $1B at
-- checkpoint $1C. Calls fn(f) once Yumetaro is in control there.
function warp(stage, cp, fn)
  local phase, t0 = "warp", 0
  return function(f)
    if phase == "warp" then
      w(0x1B, stage); w(0x1C, cp or 0); w(0x346, 0); w(0x104, 9)
      phase = "dying"; t0 = f
    elseif phase == "dying" then
      if r(0x90) == 1 and f > t0 + 60 then phase = "play"; t0 = f end
      if f > t0 + 2000 then check(false, "warp to stage " .. stage); done() end
    else
      fn(f - t0)
    end
  end
end
