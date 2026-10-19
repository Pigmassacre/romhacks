-- Star recall: press B while a star is out.
-- Hack: the old star is taken away and a new one starts charging that frame.
-- Original: B does nothing until the old star is gone.

local function charging() return r(0x91) >= 0x80 and r(0x91) < 0xD0 end

-- Hold B for 40 frames and let go: a star thrown from a standstill on frame 41.
local function throw(f) return f <= 40 end

local basic = {
  name = "recall a thrown star",
  len = 110,
  input = function(f)
    if throw(f) or (f >= 61 and f <= 100) then return pad("B") end
    return {}
  end,
  frame = function(f)
    if f == 45 then check(r(0x91) == 1, "star thrown") end
    if f == 60 then check(r(0x91) == 1, "star still out before B") end
    if f == 61 then
      if HACK then
        check(r(0x91) == 0x80, string.format("B starts a new charge at once ($91=%02x)", r(0x91)))
        check(rs("FX_T") == 2, "the old star flies home")
        check(r(0xD7) == 0, "the old star cannot be stood on")
      else
        check(r(0x91) == 1, "original: the old star stays")
      end
    end
    if HACK and f > 61 and f <= 100 and not charging() then check(false, "charging until B is let go, frame " .. f) end
    if HACK and f == 60 + SYM.GHOST_LEN then
      -- on its last frame the old star is about at the new one, over his head
      local gx = rs("FX_XTile") * 256 + rs("FX_XSub")
      local gy = rs("FX_YTile") * 256 + rs("FX_YSub")
      local tx = r(0xB8) * 256 + r(0xAE)
      local ty = r(0xA4) * 256 + r(0x9A) - 0x100
      check(math.abs(gx - tx) < 0x40 and math.abs(gy - ty) < 0x40,
        string.format("the old star reaches him (%04x,%04x vs %04x,%04x)", gx, gy, tx, ty))
    end
    if HACK and f == 61 + SYM.GHOST_LEN then check(rs("FX_T") == 0, "the ghost is gone") end
    if HACK and f == 101 then check(r(0x91) == 1, "the new star is thrown") end
  end,
}

-- Throw, let it roll, put Yumetaro on top of it, then recall it from under him.
local ridden = false
local ride = {
  name = "recall the star he is standing on",
  len = 100,
  input = function(f)
    if throw(f) or f == 85 then return pad("B") end
    return {}
  end,
  frame = function(f)
    if f == 75 then
      -- the star is rolling along the ground now: stand him on it
      w(0xB8, r(0xB9)); w(0xAE, r(0xAF))
      local y = r(0xA5) * 256 + r(0x9B) - 0xF0
      w(0xA4, y >> 8); w(0x9A, y % 256); w(0xC2, 0); w(0xCC, 0)
    end
    if f == 80 then
      ridden = r(0x365) ~= 0 and r(0x36E) >= 0x80
      check(ridden, string.format("standing on the star ($0365=%02x $D7=%02x)", r(0x365), r(0xD7)))
    end
    if f == 85 then
      if HACK then
        check(charging(), "B recalls the star under him")
        check(r(0x365) == 0, "nobody is standing on it")
      else
        check(r(0x91) == 1, "original: still riding")
      end
    end
    if HACK and f == 87 then
      check(r(0x36E) < 0x80 and s8(r(0xC2)) > 0, string.format("he falls (fl=%02x vy=%d)", r(0x36E), s8(r(0xC2))))
    end
  end,
}

local vanish = {
  name = "recall a star that is vanishing",
  len = 70,
  input = function(f)
    if throw(f) or (f >= 52 and f <= 60) then return pad("B") end
    return {}
  end,
  frame = function(f)
    if f == 50 then w(0x91, 0xD0); w(0x38D, 4) end   -- start its vanish animation
    if f == 51 then check(r(0x91) == 0xD0, "vanishing") end
    if f == 52 then
      if HACK then check(charging(), "B starts a new charge")
      else check(r(0x91) == 0xD0, "original: B waits for the vanish") end
    end
  end,
}

-- A fireball is an item: B must not take it away.
local fireball = {
  name = "a fireball is not recalled",
  len = 90,
  setup = function() w(0x36, 2); w(0x39, 1) end,   -- give him a fireball item
  input = function(f)
    if f >= 2 and f <= 42 then return pad(f <= 3 and "B U" or "B") end   -- B+Up picks the item, then charge
    if f >= 70 and f <= 72 then return pad("B") end
    return {}
  end,
  frame = function(f)
    if f == 5 then check(r(0x351) == 1, "fireball selected") end
    if f == 50 then check(r(0x91) == 1 and r(0x351) == 1, string.format("fireball thrown ($91=%02x)", r(0x91))) end
    if f == 70 then
      check(r(0x91) == 1 and r(0x351) == 1, "B leaves the fireball alone")
      check(rs("FX_T") == 0 or not HACK, "no ghost")
    end
  end,
}

-- B+Up with a fireball item while a star is out: the recall charges the fireball.
local item = {
  name = "B+Up recalls the star and charges the fireball item",
  len = 110,
  setup = function() w(0x36, 2); w(0x39, 1) end,
  input = function(f)
    if throw(f) then return pad("B") end
    if f >= 61 and f <= 100 then return pad("B U") end
    return {}
  end,
  frame = function(f)
    if f == 45 then check(r(0x91) == 1 and r(0x351) == 0, "a star is out") end
    if f == 61 and HACK then check(charging() and r(0x351) == 1, string.format("charging the fireball ($91=%02x $0351=%02x)", r(0x91), r(0x351))) end
    if f == 101 and HACK then check(r(0x91) == 1 and r(0x351) == 1 and r(0x39) == 0, "the fireball is thrown and used up") end
    if f == 61 and not HACK then check(r(0x91) == 1 and r(0x351) == 0, "original: the star stays") end
  end,
}

SCENARIOS = { basic, ride, vanish, fireball, item }
run_scenarios()
