-- A profile of where the SNES build's time goes, for tools/prof.py: each instruction's master
-- clocks, by address and by what it was part of, over PROF_FRAMES frames of a scene that
-- tests/s_lag.lua sets up. N is the NMI, I the status bar's interrupt, W the game's frame
-- before it is done ($F0 is not $AC), D the main thread after that: waiting, mostly.
local prof, last_key, last_clk = {}, nil, nil
local on = false
local ctx = {}
local ops = {}
local function on_exec(addr)
  local c = emu.getMasterClock()
  if last_key then prof[last_key] = (prof[last_key] or 0) + (c - last_clk) end
  local lo = addr & 0xFFFF
  if (addr >> 16) & 0x7F == 0 and lo == NMI_EMU then ctx[#ctx + 1] = "N"
  elseif (addr >> 16) & 0x7F == 0 and lo == IRQ_EMU then ctx[#ctx + 1] = "I" end
  local k = ctx[#ctx]
  if not k then k = emu.read(0xF0, emu.memType.snesMemory) == 0xAC and "D" or "W" end
  last_key, last_clk = k .. string.format("%06X", addr), c
  local op = ops[addr]
  if not op then op = emu.read(addr, emu.memType.snesMemory); if addr & 0xFFFF >= 0x8000 then ops[addr] = op end end
  if op == 0x40 and #ctx > 0 then ctx[#ctx] = nil end
end
ON_PLAY = function(t)
  if t == (PROF_FROM or 120) then on = true; emu.addMemoryCallback(on_exec, emu.callbackType.exec, 0, 0xFFFFFF) end
  if t == (PROF_FROM or 120) + PROF_FRAMES then
    local h = io.open(OUT .. "prof_" .. SCENE .. ".txt", "w")
    for a, c in pairs(prof) do h:write(a, " ", c, "\n") end
    h:close()
    emu.stop(0)
  end
end
