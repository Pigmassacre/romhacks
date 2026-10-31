-- A late frame's NMI can land while Castlevania's sound effect routine ($C1A7)
-- has bank 0 mapped, without noting it in $27. The hack's late frame put back
-- the noted bank, and returned into the sound code with the wrong bank under
-- it: the CPU ran off into data and stopped dead, on stage 12 in a whole run.
-- Here the routine is made to wait for the NMI just there, with a jump to
-- itself patched into it, taken out again as the NMI comes.
local PRG = emu.memType.nesPrgRom
local AT = 15 * 0x4000 + (0xC1BC - 0xC000)
local saved = {emu.read(AT, PRG), emu.read(AT + 1, PRG), emu.read(AT + 2, PRG)}
local armed, landed, finished, lastfc, still = false, 0, 0, nil, 0
local function arm() emu.write(AT, 0x4C, PRG); emu.write(AT + 1, 0xBC, PRG); emu.write(AT + 2, 0xC1, PRG); armed = true end
local function disarm() for i = 1, 3 do emu.write(AT + i - 1, saved[i], PRG) end; armed = false end
emu.addMemoryCallback(function()
  if armed then disarm(); landed = landed + 1 end
end, emu.callbackType.exec, 0xC0C0, 0xC0C0)
local wrong = 0
-- about to call into bank 0: is it there?
emu.addMemoryCallback(function()
  if landed > finished then
    finished = landed
    for i = 0, 3 do if emu.read(0x8187 + i, M) ~= emu.read(0x0187 + i, PRG) then wrong = wrong + 1; break end end
  end
end, emu.callbackType.exec, 0xC1BF, 0xC1BF)
loadstate_raw("castle")
INPUT = function(f) return {right = f % 90 < 70, b = f % 6 == 0, a = f % 16 < 4} end
FRAME = function(f)
  w(0x118, 9); w(0x5B, 0x40)
  if f > 10 and f % 40 == 0 and not armed and landed < 12 then arm() end
  local fc = r(0x1A)
  if fc == lastfc then still = still + 1 else still = 0 end
  lastfc = fc
  if still > 200 then
    if armed then disarm() end
    check(false, string.format("the game goes on (stopped at %04x, after %d landed)", emu.getState()["cpu.pc"], landed)); done(); return
  end
  if f == 1200 then
    check(landed >= 8, string.format("the NMI landed in the sound code (%d times)", landed))
    check(wrong == 0, string.format("and the sound code had its bank (the wrong one %d times)", wrong))
    check(r(0x18) == 5, "the game goes on")
    done()
  end
end
