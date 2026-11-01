-- A tour of the whole game for tools/record.py --tour: every checkpoint of every
-- stage, a sweep across each stage's map to meet its objects and boss, clearing each
-- stage, the world map, both endings and a game over. It warps by writing RAM, and goes before
-- s_record.lua, which logs those writes.
FRAMES = 2000000
local PLAY = 800
local SWEEP = 3400
local sweep_x, sweep_s = 2, 0
local steps = {}
local function stage_steps(stage)
  for cp = 0, 3 do steps[#steps + 1] = {kind = "warp", stage = stage, cp = cp} end
  steps[#steps + 1] = {kind = "warp", stage = stage, cp = 0, sweep = true}
end
for stage = 0, 4 do
  stage_steps(stage)
  steps[#steps + 1] = {kind = "clear", stage = stage}
end
stage_steps(5)
-- Clearing stage 6 (number 5) without the treasures: the sad ending, then the title.
steps[#steps + 1] = {kind = "clear", stage = 5}
steps[#steps + 1] = {kind = "gameover"}
steps[#steps + 1] = {kind = "warp", stage = 5, cp = 0}
-- With all the treasures it opens the secret stage, and that leads to the real ending.
steps[#steps + 1] = {kind = "clear", stage = 5, treasures = true}
stage_steps(6)
steps[#steps + 1] = {kind = "ending"}

local i, phase, t0 = 0, "boot", 0
local marks = io.open(OUT .. "tour.txt", "w")
local function mark(f, what)
  marks:write(f, " ", what, "\n"); marks:flush()
  local h = io.open(OUT .. "shot_" .. what .. ".png", "wb")
  h:write(emu.takeScreenshot()); h:close()
end
local function start_step(f)
  i = i + 1
  local st = steps[i]
  t0 = f
  if not st then
    marks:close()
    FRAMES = 0
    return
  end
  if st.kind == "warp" then
    poke(0x1B, st.stage); poke(0x1C, st.cp); poke(0x346, 0); poke(0x104, 9)
    phase = "dying"
  elseif st.kind == "clear" then
    poke(0x1B, st.stage); poke(0xEB, 1); poke(0xEA, 1); poke(0x104, 9)
    if st.treasures then
      for a = 0x105, 0x10A do poke(a, 1) end
    end
    phase = "clearing"
  elseif st.kind == "ending" then
    poke(0x1B, 6); poke(0xEB, 1); poke(0xEA, 1); poke(0x54, 1)
    phase = "ending"
  else
    poke(0x104, 0); poke(0x346, 0)
    phase = "gameover"
  end
  if st.stage then sweep_x, sweep_s = 2, 0 end
end

-- At an idle NMI the bank at $8000 tells the world map and title apart from a stage.
function on_map() return r(0x40) == 0x1C or r(0x40) == 0x1B end
function in_stage() return r(0x90) == 1 and not on_map() end

ON_NMI = function(f)
  local st = steps[i]
  if phase == "boot" then
    if r(0x90) == 1 and f > 600 then start_step(f) end
  elseif phase == "dying" then
    if in_stage() and f > t0 + 60 then
      phase = "play"; t0 = f
      sweep_x, sweep_s = 2, 0
      mark(f, string.format("s%d_c%d", st.stage, st.cp))
    elseif f > t0 + 1500 then
      marks:write(f, " stuck ", i, "\n"); start_step(f)
    end
  elseif phase == "play" then
    if r(0x346) < 3 then poke(0x346, 3) end
    if st.sweep then
      -- Hop along the map: every 45 frames, 7 columns on, and down to the next
      -- screen at the end of a row.
      if (f - t0) % 45 == 0 then
        sweep_x = sweep_x + 7
        if sweep_x > 126 then
          sweep_x = 2
          sweep_s = (sweep_s + 1) % 4
        end
        poke(0xB8, sweep_x); poke(0xA4, sweep_s * 16 + 3); poke(0xC2, 0)
      end
      if (f - t0) % 400 == 200 then mark(f, string.format("s%d_sweep_%05d", st.stage, f - t0)) end
      if f > t0 + SWEEP then start_step(f) end
    else
      if f == t0 + 700 then mark(f, string.format("s%d_c%d_later", st.stage, st.cp)) end
      if f > t0 + PLAY then start_step(f) end
    end
  elseif phase == "clearing" then
    if f == t0 + 300 then mark(f, string.format("clear%d%s_a", st.stage, st.treasures and "t" or "")) end
    if f == t0 + 700 then mark(f, string.format("clear%d%s_b", st.stage, st.treasures and "t" or "")) end
    if (f > t0 + 300 and in_stage()) or f > t0 + 4000 then start_step(f) end
  elseif phase == "ending" then
    if (f - t0) % 1500 == 800 then mark(f, string.format("ending_%05d", f - t0)) end
    if f > t0 + 12000 then start_step(f) end
  elseif phase == "gameover" then
    if f == t0 + 400 then mark(f, "gameover") end
    if (f > t0 + 800 and in_stage()) or f > t0 + 2500 then start_step(f) end
  end
  if FRAMES == 0 or f > 150000 then FRAMES = f end
end

PICK_INPUT = function(f)
  if phase == "ending" then return {} end
  if phase == "boot" or phase == "clearing" or phase == "gameover" or phase == "dying" then
    -- Start only away from play: in a stage it pauses.
    -- ($D0 and up is dying or the game over screen, which waits for it.)
    return {start = (r(0x90) == 0 or r(0x90) >= 0xD0 or on_map()) and f % 60 < 5}
  end
  local beat = (f - t0) % 400
  return {right = beat < 300, left = beat >= 310 and beat < 390,
          a = f % 53 < 20, b = f % 150 < 60, up = f % 700 < 30, down = f % 900 < 20}
end
