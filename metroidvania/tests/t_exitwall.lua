-- Landing against the wall beside a stage's exit: the door opens. Stage 7's
-- exit is at screen x $E8, with a wall at $F0; Samus stops against it at $EC,
-- one pixel past Castlevania's window. She used to stand there until she
-- stepped back.
local phase, died = "towarp", false
loadstate_raw("castle", function() end)
INPUT = function(f) return phase == "wall" and pad("R") or {} end
FRAME = function(f)
  if phase ~= "towarp" and phase ~= "warp" then w(0x118, 9); w(0x5B, 0x40) end
  if phase == "towarp" and r(0x18) == 5 then
    w(0x28, 7); w(0x29, 7); w(0x118, 0); w(0x117, 0x10); w(0x45, 0); w(0x2A, 9); phase = "warp"
  end
  if r(0x18) == 6 then died = true end
  if phase == "warp" and not died and r(0x18) == 5 then w(0x5B, 0); w(0x113, 0); w(0x45, 0) end
  if phase == "warp" and died and r(0x18) == 5 and r(0x19) == 6 and r(0x28) == 7 then
    -- into the stage's other half, as the stairs would, over the door's ledge,
    -- from above and out of the window
    w(0x46, 1); phase = "load"
    w(0x19, 0); w(0x18, 5)
  end
  if phase == "load" and r(0x18) == 5 and r(0x19) == 6 and (r(0x126) & 1) == 1 then
    w(0x122, 0xEC); w(0x123, 2); w(0x124, 0x70); w(0x2E, 0); w(0x2F, 2); phase = "wall"
    w(0x10B, 0x18); w(0x109, 0)
  end
  if phase == "wall" and r(0x18) == 8 then
    check(true, string.format("the door opens, from x %02x", r(0x38C)))
    done()
  end
  if f > 1500 then check(false, string.format("the door opened (%s, mode %02x/%02x x %02x%02x y %02x sx %02x)", phase, r(0x18), r(0x19), r(0x123), r(0x122), r(0x124), r(0x38C))); done() end
end
