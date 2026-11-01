-- Input sequences for the physics comparison: each runs from Samus standing
-- still on flat ground, at screen x `x` (default $30), where neither game
-- scrolls during it. (Metroid's scrolling can skip a frame of the game;
-- that is not part of how Samus moves.) Shared by tools/record_physics.lua
-- (in Metroid) and tests/t_physics.lua (in the hack).
SEQUENCES = {
  {name = "jump", len = 90, input = function(f) return f <= 60 and pad("A") or {} end},
  {name = "hop", len = 60, input = function(f) return f <= 8 and pad("A") or {} end},
  {name = "run", len = 70, input = function(f) return f <= 60 and pad("R") or {} end},
  {name = "runleft", x = 0xD0, len = 50, input = function(f) return f <= 40 and pad("L") or {} end},
  {name = "runjump", x = 0x10, len = 90, input = function(f)
      if f <= 20 then return pad("R") end
      if f <= 70 then return pad("R A") end
      return pad("R") end},
  {name = "turn", len = 60, input = function(f) return f <= 20 and pad("R") or (f <= 45 and pad("L") or {}) end},
  {name = "airturn", x = 0x50, len = 80, input = function(f)
      if f <= 10 then return pad("R") end
      if f <= 30 then return pad("R A") end
      if f <= 50 then return pad("L A") end
      return {} end},
  {name = "ball", len = 60, input = function(f)
      if f <= 4 then return pad("D") end
      if f <= 40 then return pad("R") end
      return {} end},
  {name = "unroll", len = 50, input = function(f)
      if f <= 4 then return pad("D") end
      if f >= 20 and f <= 22 then return pad("U") end
      return {} end},
  {name = "shoot", len = 60, input = function(f) return (f % 12 < 2) and pad("B") or {} end},
  {name = "holdfire", len = 90, input = function(f) return pad("B") end},
  {name = "aimup", len = 60, input = function(f)
      if f % 15 == 5 then return pad("U B") end
      return pad("U") end},
  {name = "runshoot", len = 60, input = function(f) return (f % 10 < 2) and pad("R B") or pad("R") end},
  {name = "spinshoot", len = 70, input = function(f)
      if f <= 10 then return pad("R") end
      if f == 30 then return pad("R A B") end
      return pad("R A") end},
  {name = "missile", len = 80, input = function(f)
      if f == 2 then return pad("E") end
      if f % 25 == 5 then return pad("B") end
      if f > 40 and f % 25 == 15 then return pad("U B") end
      return f > 40 and pad("U") or {} end},
  {name = "bomb", len = 130, input = function(f)
      if f <= 4 then return pad("D") end
      if f == 10 then return pad("B") end
      return {} end},
  {name = "bombroll", len = 130, input = function(f)
      if f <= 4 then return pad("D") end
      if f == 10 then return pad("B") end
      if f > 12 and f <= 30 then return pad("R") end
      if f > 30 and f <= 42 then return pad("L") end
      return {} end},
  {name = "bombs", len = 140, input = function(f)
      if f <= 4 then return pad("D") end
      if f % 12 == 10 then return pad("B") end
      return {} end},
  {name = "jumpaim", len = 70, input = function(f)
      if f <= 40 then return (f > 25 and f % 6 == 0) and pad("A U B") or pad("A U") end
      return {} end},
}

-- What is compared each frame: Samus's position (from where she started),
-- her animation frame (Metroid's frame number), and her first projectile:
-- its status and position (from Samus's start), 0 when there is none.
