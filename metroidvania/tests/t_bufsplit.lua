-- Stage 6's crushers write many small pieces of the screen. With the HUD's
-- colours, that took the update buffer past the vertical blank: the screen came
-- back on too late for the top of the picture and sprite 0, the split gave up
-- lines late, and the picture jumped, 127 times here. The status bar's blank
-- tiles aren't written any more, and what doesn't fit waits for the next frame.
local way = "L"
local function x() return r(0x122) + 256 * r(0x123) end
local bad, on, blank, phase, t0, died = 0, 0, 0, "warp", 0, false
emu.addMemoryCallback(function(a, v)
  if v == 0 or phase ~= "watch" or r(0x18) ~= 5 or r(0x19) ~= 6 then return end
  local l = emu.getState()["ppu.scanline"]
  if l >= 200 and l ~= 261 then blank = blank + 1
  elseif l == 44 then on = on + 1
  else bad = bad + 1 end
end, emu.callbackType.write, 0x2001, 0x2001)
loadstate_raw("castle", function()
  w(0x28, 6); w(0x29, 6); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9)
end)
INPUT = function(f)
  if phase == "fly" then return pad("L") end
  if phase == "watch" then
    if x() < 0x60 then way = "R" elseif x() > 0x220 then way = "L" end
    local t = pad(way); t.b = f % 6 == 0; return t
  end
  return {}
end
FRAME = function(f)
  if phase ~= "warp" then w(0x118, 9); w(0x2A, 9); w(0x43, 4) end
  if r(0x18) == 6 then died = true end
  if phase == "warp" and died and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 6 and (r(0x126) & 1) == 1 then phase = "fly" end
  if phase == "fly" or phase == "watch" then w(0x1C0, 0x80); w(0x124, 0x7D); w(0x10B, 0); w(0x109, 0); w(0x5B, 0) end
  if phase == "fly" and x() < 0x170 then phase = "watch"; t0 = f end
  if phase == "watch" and f == t0 + 2500 then
    check(on > 2000, string.format("the split seen (%d frames)", on))
    check(bad == 0, string.format("the screen always came on in time (%d times not)", bad))
    done()
  end
  if f > 6000 then check(false, "got there: " .. phase); done() end
end
