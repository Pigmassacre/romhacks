-- Morph ball bombs: B in the ball lays one, as in Metroid, and its blast throws her
-- with no damage and no blinking (physics checks the throw against Metroid). The
-- blast hurts what's near it through Castlevania's subweapon code, a limited number
-- of times, and breaks blocks. With zombies coming along the hall, then at the
-- hall's breakable block ($3F8, y $98).
local phase, t0, en, hearts, top, hidden = "ball", 0, 0, 0, 0, 0
local hits, maxBlast, inBlast, posed, lastai = 0, 0, {}, 0, {}
loadstate_raw("castle")
INPUT = function(f)
  if phase == "ball" then return f - t0 < 4 and pad("D") or {} end
  if phase == "lay" and f == t0 + 2 then return pad("B") end
  if phase == "warpblock" then return pad("R") end
  if phase == "crowd" then
    if f - t0 < 4 then return pad("D") end
    local t = {b = f % 16 == 0}
    if (f - t0) % 300 < 200 then t.right = true else t.left = true end
    return t
  end
  return {}
end
FRAME = function(f)
  if phase == "ball" and f == t0 + 20 then
    check(r(0x100) == 3, "she is in the ball")
    en = r(0x118) * 256 + r(0x117); hearts = r(0x71)
    phase = "lay"; t0 = f; top = r(0x124); hidden = 0
  end
  if phase == "lay" then
    if f == t0 + 6 then check(r(0x7CF) == 9, string.format("B lays a bomb (status %02x)", r(0x7CF))); shot("bomb") end
    if r(0x7CF) == 0x0A then
      if r(0x124) < top then top = r(0x124) end
    end
    if f == t0 + 56 then shot("blast1") end
    if f == t0 + 64 then shot("blast2") end
    if f == t0 + 72 then shot("blast3") end
    if f == t0 + 120 then
      check(r(0x7CF) == 0, "the bomb is gone")
      check(top < 0xB0, string.format("the blast threw her (up to y %02x)", top))
      check(r(0x118) * 256 + r(0x117) == en, "no damage")
      check(r(0x71) == hearts, "and it doesn't cost a heart")
      phase = "crowd"; t0 = f
    end
  end
  if phase == "crowd" then
    w(0x118, 9)
    for s = 0, 2 do
      local ai, st = r(0x434 + 0x14 + s), r(0x7CF + s)
      if st == 0x0A then
        if ai == 0x17 and r(0x31C + 0x14 + s) ~= 0 then posed = posed + 1 end
        if lastai[s] == 0x17 and ai == 0x32 then
          hits = hits + 1
          inBlast[s] = (inBlast[s] or 0) + 1
          if inBlast[s] > maxBlast then maxBlast = inBlast[s] end
        end
      else
        inBlast[s] = 0
      end
      lastai[s] = ai
    end
    if f == t0 + 1500 then
      check(hits >= 2, string.format("blasts hit things (%d hits)", hits))
      check(maxBlast <= 2, string.format("no more than twice each (%d)", maxBlast))
      check(posed == 0, "a blast's dagger never has a sprite")
      phase = "warpblock"; t0 = f
    end
  end
  if phase == "warpblock" then
    w(0x1C0, 0x80); w(0x124, 0x9E); w(0x10B, 0); w(0x109, 0)
    for i = 4, 0x13 do if r(0x434 + i) == 0x01 or r(0x434 + i) == 0x03 then w(0x434 + i, 0); w(0x31C + i, 0) end end
    if r(0x122) + 256 * r(0x123) >= 0x3E0 then
      w(0x1C0, 0)
      w(0x7CF, 8); w(0x7E4, 0xF0); w(0x7E7, 3); w(0x7EA, 0x98)   -- a bomb beside the block
      phase = "block"; t0 = f
    end
  end
  if phase == "block" then
    w(0x124, 0x9E); w(0x10B, 0); w(0x109, 0)
    if (r(0x146) & 1) ~= 0 then check(true, "a blast breaks a block"); shot("broken"); done(); return end
    if f > t0 + 200 then check(false, "a blast breaks a block"); shot("unbroken"); done(); return end
  end
  if f > 6000 then check(false, "got through (" .. phase .. ")"); done() end
end
