-- Not a test: how much of each frame the NMI (all of Castlevania's game
-- logic, and the hack's) takes, from the castle savestate with fixed input.
-- Reports the average and worst NMI in CPU cycles (a frame is 29780), how
-- many frames ran late (the next NMI came before this one ended), and the
-- hack's routines by FarCall number.
local t, n, sum, worst, late = 0, 0, 0, 0, 0
local ft, fx, depth, tot, cnt = {}, {}, 0, {}, {}
local on = false
emu.addMemoryCallback(function() if on then t = emu.getState()["cpu.cycleCount"] end end, emu.callbackType.exec, 0xC052, 0xC052)
emu.addMemoryCallback(function()
  if not on or t == 0 then return end
  local c = emu.getState()["cpu.cycleCount"] - t; t = 0
  n = n + 1; sum = sum + c; if c > worst then worst = c end
end, emu.callbackType.exec, 0xC0B9, 0xC0B9)
emu.addMemoryCallback(function() if on then late = late + 1 end end, emu.callbackType.exec, 0xC0C0, 0xC0C0)
emu.addMemoryCallback(function()
  depth = depth + 1; ft[depth] = emu.getState()["cpu.cycleCount"]; fx[depth] = emu.getState()["cpu.x"]
end, emu.callbackType.exec, 0xFF2A, 0xFF2A)
emu.addMemoryCallback(function()
  if depth < 1 then return end
  local x = fx[depth]; local c = emu.getState()["cpu.cycleCount"] - ft[depth]; depth = depth - 1
  if on then tot[x] = (tot[x] or 0) + c; cnt[x] = (cnt[x] or 0) + 1 end
end, emu.callbackType.exec, 0xFF37, 0xFF37)
loadstate_raw("castle", function() on = true; depth = 0 end)
INPUT = function(f)
  local p = f % 60
  return {right = p < 40, b = p % 6 == 0, a = p > 45 and p < 50}
end
FRAME = function(f)
  if f == 1200 then
    log(string.format("NMI: average %d cycles, worst %d; %d late frames in %d", sum // n, worst, late, n))
    for x, v in pairs(tot) do log(string.format("  FarCall %2d: %5d cycles a call, %d calls", x, v // cnt[x], cnt[x])) end
    log("PASS"); done()
  end
end
