-- Record Samus's position in Metroid for each sequence in tests/physics_inputs.lua.
-- Run with: python3 tools/lua.py tools/record_physics.lua Metroid.nes
-- Writes tests/ref/physics.txt: per sequence, per step: Samus's dx dy from the
-- start, her animation frame, and the first projectile's status and dx dy.
--
-- Metroid's main loop sometimes takes longer than a frame (a lag frame), so
-- this counts Samus's updates (calls to UpdateSamus, $CC0D) instead of
-- frames, and gives each update its own input.
dofile(REPO .. "/tests/physics_inputs.lua")
local out = io.open(REPO .. "/tests/ref/physics.txt", "w")
local state, si, steps, x0, y0, START = "boot", 1, 0, 0, 0, nil
local function pos() return r(0x30C) * 256 + r(0x30E), r(0x30D) end
-- An open, flat room: Metroid's room RAM ($6000, 32x30 tiles per name table)
-- all air ($FF) above a solid floor from row 24 down. Samus stands at $B1.
local function flatten()
  for nt = 0, 1 do
    for row = 0, 29 do
      for col = 0, 31 do
        emu.write(0x6000 + nt * 0x400 + row * 32 + col, row >= 24 and 0x10 or 0xFF, emu.memType.nesDebug)
      end
    end
  end
end
local function begin()
  w(0x30E, SEQUENCES[si].x or 0x30)
  w(0x2D, 0)   -- the frame count: bombs' fuses go by it
  w(0x6878, (r(0x6878) & 0xB7) | (SEQUENCES[si].gear or 0))   -- Screw Attack, Wave Beam
  x0, y0 = pos(); steps = 0; state = "run"
  out:write("seq " .. SEQUENCES[si].name .. "\n")
end
-- Each update: count it as it starts (its input was read in the NMI before),
-- and record where things are once Samus has moved ($CC17, just after
-- UpdateSamus's jsr GoSamusHandler). Metroid moves projectiles before Samus,
-- as the hack does.
emu.addMemoryCallback(function()
  if state == "run" then steps = steps + 1 end
end, emu.callbackType.exec, 0xCC0D, 0xCC0D)
emu.addMemoryCallback(function()
  if state ~= "run" then return end
  local x, y = pos()
  -- the first projectile: Metroid's slot $03D0
  local bs, bx, by = r(0x3D0), 0, 0
  if bs ~= 0 then bx = r(0x3DC) * 256 + r(0x3DE) - x0; by = r(0x3DD) - y0 end
  out:write(string.format("%d %d %02x %02x %d %d\n", x - x0, y - y0, r(0x303), bs, bx, by))
  if steps >= SEQUENCES[si].len then
    si = si + 1
    if si > #SEQUENCES then out:close(); state = "done"; return end
    emu.loadSavestate(START)
    begin()
  end
end, emu.callbackType.exec, 0xCC17, 0xCC17)
INPUT = function(f)
  if state == "boot" then return {start = f < 400 and (f % 90) < 3 and f > 60} end
  if state == "run" then return SEQUENCES[si].input(steps + 1) end
  return {}
end
FRAME = function(f)
  if state == "done" then log("done"); stop() end
  -- in Brinstar after the intro, standing (status 0, or $FF before the first input)
  if state == "boot" and f > 1100 and r(0x1E) == 3 and (r(0x300) == 0 or r(0x300) == 0xFF) then
    state = "wait"
    local id
    id = emu.addMemoryCallback(function()
      emu.removeMemoryCallback(id, emu.callbackType.exec, 0x8000, 0xFFFF)
      flatten(); w(0x30D, 0xB1); for a = 0x310, 0x313 do w(a, 0) end
      w(0x6878, r(0x6878) | 0x11)     -- bombs and the Maru Mari, which the hack gives Samus from the start
      w(0x6879, 5); w(0x687A, 5)       -- 5 missiles, as the hack's 5 hearts
      w(0x300, 0); w(0x305, 0x07); w(0x306, 0x08); w(0x303, 0x08); w(0x304, 0)   -- standing, as the hack starts
      START = emu.createSavestate()
      begin()
    end, emu.callbackType.exec, 0x8000, 0xFFFF)
  end
end
