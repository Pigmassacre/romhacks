-- Frame budget, per stage, on gameplay frames:
--  * spare: cycles from the main loop starting to wait for the NMI ($F29F)
--    to the NMI. 0 or missing means a lag frame.
--  * hack: cycles spent inside the hack's routines (from FarCall's
--    `jsr HackEntry` to its return). Hack ROM only.
-- A frame is 29780 cycles.
local cyc = function() return emu.getState()["cpu.cycleCount"] end
local waitAt, t0, hackc = nil, 0, 0
local stats = {}
local function stat(name, v)
  local s = stats[name] or {n = 0, sum = 0, max = 0, min = 1e9}
  s.n = s.n + 1; s.sum = s.sum + v
  if v > s.max then s.max = v end
  if v < s.min then s.min = v end
  stats[name] = s
end
local JSR = SYM.FarCall_Jsr
emu.addMemoryCallback(function() waitAt = cyc() end, emu.callbackType.exec, 0xF29F, 0xF29F)
if HACK then
  emu.addMemoryCallback(function() t0 = cyc() end, emu.callbackType.exec, 0xE28F, 0xE28F)
  emu.addMemoryCallback(function() hackc = hackc + cyc() - t0 end, emu.callbackType.exec, 0xE292, 0xE292)
end
emu.addEventCallback(function()
  if r(0x90) == 1 then
    stat("spare", waitAt and (cyc() - waitAt) or 0)
    if not waitAt then stat("lag", 1) end
    if HACK then stat("hack", hackc) end
  end
  waitAt = nil; hackc = 0
end, emu.eventType.nmi)

local stage = 1
INPUT = function(f)
  local p = math.floor(f / 60) % 4
  return {right = p < 3, left = p == 3, a = (f % 31) < 12, b = (f % 47) < 38}
end
FRAME = function(f)
  if f % 1500 == 0 then
    local s, h = stats.spare, stats.hack
    if s then
      log(string.format("stage %d: spare min %5d avg %5d | hack max %4d avg %4d | %4d frames, %3d lag",
        stage, s.min, s.sum // s.n, h and h.max or 0, h and (h.sum // h.n) or 0, s.n, stats.lag and stats.lag.n or 0))
    end
    stats = {}
    stage = stage + 1
    if stage > 7 then done() return end
    w(0x1B, stage - 1); w(0x1C, 0); w(0x346, 0); w(0x104, 9)
  end
end
