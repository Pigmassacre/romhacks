-- How often the game misses a frame, on either machine, for tools/lag.py. A frame is lost
-- when the NMI comes and the game has not finished ($F0 is not $AC). On the SNES it also
-- logs the line the beam is on as the game finishes each frame, at frame_done.
local M = SNES and emu.memType.snesMemory or emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function poke(a, v) emu.write(a, v, SNES and emu.memType.snesWorkRam or emu.memType.nesDebug) end
local phase, t0, nmi = "boot", 0, 0
local log = io.open(OUT .. (SNES and "snes" or "nes") .. "_" .. SCENE .. ".txt", "w")
local function on_map() return r(0x40) == 0x1C or r(0x40) == 0x1B end
local function in_stage() return r(0x90) == 1 and not on_map() end
local done_line = -1

local function on_nmi()
  nmi = nmi + 1
  local f = nmi
  if phase == "boot" then
    if r(0x90) == 1 and f > 600 then
      poke(0x1B, STAGE); poke(0x1C, CP); poke(0x346, 0); poke(0x104, 9)
      phase = "dying"; t0 = f
    end
  elseif phase == "dying" then
    if in_stage() and f > t0 + 60 then
      if BOSS then poke(0xB8, BOSS[1]); poke(0xA4, BOSS[2]); poke(0xC2, 0) end
      phase = "play"; t0 = f
    end
  else
    -- Health kept at its most, $2B: more than that sends the status bar's loop round 256 times.
    if r(0x346) < r(0x2B) then poke(0x346, r(0x2B)) end
    if r(0x104) < 9 then poke(0x104, 9) end
    if ON_PLAY then ON_PLAY(f - t0) end
    if SHOT_AT and SHOT_AT[f - t0] then
      local h = io.open(OUT .. (SNES and "snes" or "nes") .. "_" .. SCENE .. "_" .. (f - t0) .. ".png", "wb")
      h:write(emu.takeScreenshot()); h:close()
    end
    if f > t0 + 120 then
      log:write(string.format("%d %d %d %02X %02X %02X %02X %02X\n", f - t0, r(0xF0) == 0xAC and 1 or 0, done_line,
        r(0x4A), r(0xB8), r(0xA4), r(0xFD), r(0x90)))
    end
    done_line = -1
    if f > t0 + 120 + FRAMES then log:close(); emu.stop(0) end
  end
end
if SNES then
  for b = 0xA0, 0xBF do emu.addMemoryCallback(on_nmi, emu.callbackType.exec, b * 65536 + 0xE9C6, b * 65536 + 0xE9C6) end
  local function on_done()
    if done_line < 0 then done_line = emu.getState()["ppu.scanline"] end
  end
  for b = 0xA0, 0xBF do emu.addMemoryCallback(on_done, emu.callbackType.exec, b * 65536 + FRAME_DONE, b * 65536 + FRAME_DONE) end
else
  emu.addMemoryCallback(on_nmi, emu.callbackType.exec, 0xE9C6, 0xE9C6)
end

local function pick(f)
  if phase ~= "play" then
    return {start = (r(0x90) == 0 or r(0x90) >= 0xD0 or on_map()) and f % 60 < 5}
  end
  if not MOVE then return {} end
  local t = f - t0
  local beat = t % 200
  return {right = beat < 90, left = beat >= 110 and beat < 170, a = f % 41 < 16, b = f % 97 < 50}
end
emu.addEventCallback(function() emu.setInput(pick(nmi), 0) end, emu.eventType.inputPolled)
