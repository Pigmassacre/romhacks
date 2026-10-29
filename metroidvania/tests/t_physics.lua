-- Samus moves exactly as in Metroid: for each sequence in physics_inputs.lua,
-- her position, animation frame and first shot, frame by frame, must match
-- tests/ref/physics.txt, recorded in
-- Metroid (tools/record_physics.lua). Both run on open, flat ground: here
-- Castlevania's collision map is cleared to a floor under Samus, and its
-- enemies are removed.
dofile(REPO .. "/tests/physics_inputs.lua")
local ref, cur = {}, nil
for line in io.lines(REPO .. "/tests/ref/physics.txt") do
  local n = line:match("^seq (%S+)")
  if n then cur = {}; ref[n] = cur
  else
    local t = {}
    for v in line:gmatch("%S+") do t[#t + 1] = v end
    cur[#cur + 1] = {tonumber(t[1]), tonumber(t[2]), tonumber(t[3], 16), tonumber(t[4], 16), tonumber(t[5]), tonumber(t[6])}
  end
end

local function pos() return r(0x123) * 256 + r(0x122), r(0x124) end
-- Castlevania's collision map: 2 screens x 22 rows of 8 bytes (4 cells a byte),
-- rows from y = $30. Samus stands at $C1, on the row at $D0.
local function flatten()
  for scr = 0, 1 do
    for row = 0, 21 do
      for b = 0, 7 do
        w(0x5A0 + scr * 0xB0 + row * 8 + b, (row >= (0xD0 - 0x30) / 8) and 0x55 or 0)
      end
    end
  end
  for x = 4, 0x1B do if x < 0x14 or x > 0x16 then w(0x434 + x, 0) end end   -- not $14-$16: her shots
end

local START, si, sf, x0, y0 = nil, 1, 0, 0, 0
-- at the sequence's screen x (the scroll is 0 here)
function place()
  w(0x122, SEQUENCES[si].x or 0x30); w(0x123, 0)
  x0, y0 = pos()
end
local state = "start"
local bad = 0
loadstate_raw("castle", function()
  flatten(); w(0x124, 0xC1)
  w(0x70, 0)            -- no whip upgrade: the short beam, as Metroid starts
  w(0x71, 5); w(0x11B, 0)   -- 5 hearts (missiles), not armed
  -- no leftover sub-pixel motion (zeroed in Metroid too)
  for a = 0x10C, 0x10F do w(a, 0) end
  START = emu.createSavestate(); place(); state = "run"
end)
INPUT = function(f)
  if state == "run" then return SEQUENCES[si].input(sf + 1) end
  return {}
end
FRAME = function(f)
  if state ~= "run" then return end
  flatten()
  sf = sf + 1
  local x, y = pos()
  local want = ref[SEQUENCES[si].name][sf]
  local bs, bx, by = r(0x7CF), 0, 0
  if bs ~= 0 then bx = r(0x7E7) * 256 + r(0x7E4) - x0; by = r(0x7EA) - y0 end
  local got = {x - x0, y - y0, r(0x103), bs, bx, by}
  local same = true
  for k = 1, 6 do if got[k] ~= want[k] then same = false end end
  if not same and bad < 5 then
    bad = bad + 1
    log(string.format("     %s frame %d: Samus %d,%d frame %02x, shot %02x %d,%d; Metroid %d,%d frame %02x, shot %02x %d,%d",
      SEQUENCES[si].name, sf, got[1], got[2], got[3], got[4], got[5], got[6], want[1], want[2], want[3], want[4], want[5], want[6]))
  end
  if sf >= SEQUENCES[si].len then
    check(bad == 0, SEQUENCES[si].name .. " matches Metroid frame by frame")
    bad = 0
    si = si + 1
    if si > #SEQUENCES then done() return end
    state = "load"
    onexec(function() emu.loadSavestate(START); place(); sf = 0; state = "run" end)
  end
end
