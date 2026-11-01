-- A tour of the whole game for tools/record.py --tour: every checkpoint of every
-- stage, clearing each stage, the ending and a game over. It warps by writing RAM,
-- and goes before s_record.lua, which logs those writes.
FRAMES = 2000000
local PLAY = PLAY or 500
local steps = {}
for stage = 0, 6 do
  for cp = 0, 3 do steps[#steps + 1] = {kind = "warp", stage = stage, cp = cp} end
  steps[#steps + 1] = {kind = "clear", stage = stage}
end
steps[#steps + 1] = {kind = "ending"}
steps[#steps + 1] = {kind = "gameover"}

local i, phase, t0 = 0, "boot", 0
local marks = {write=function() end, flush=function() end, close=function() end}
local function mark(f, what)
  if SHOTS then
    local h = io.open(OUT .. "shot_" .. what .. ".png", "wb")
    h:write(emu.takeScreenshot()); h:close()
    if DUMP_NT then DUMP_NT(what) end
    print(what)
    local l = io.open(OUT .. "marks.txt", "a")
    l:write(string.format("%d %s 4A=%02X 90=%02X 1B=%02X 1C=%02X\n", f, what, r(0x4A), r(0x90), r(0x1B), r(0x1C))); l:close()
  end
  marks:write(f, " ", what, "\n"); marks:flush()
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
    poke(0x1B, st.stage); poke(0x54, st.stage == 6 and 0 or 0); poke(0xEB, 1); poke(0xEA, 1); poke(0x104, 9)
    phase = "clearing"
  elseif st.kind == "ending" then
    poke(0x1B, 6); poke(0xEB, 1); poke(0xEA, 1)
    phase = "ending"
  else
    poke(0x104, 0); poke(0x346, 0)
    phase = "gameover"
  end
end

ON_NMI = function(f)
  local st = steps[i]
  if phase == "boot" then
    if r(0x90) == 1 and f > 600 then start_step(f) end
  elseif phase == "dying" then
    if r(0x90) == 1 and f > t0 + 60 then
      phase = "play"; t0 = f
      mark(f, string.format("s%d_c%d", st.stage, st.cp))
    elseif f > t0 + 1500 then
      marks:write(f, " stuck ", i, "\n"); start_step(f)
    end
  elseif phase == "play" then
    if r(0x346) < 3 then poke(0x346, 3) end
    if f == t0 + 300 then mark(f, string.format("s%d_c%d_later", st.stage, st.cp)) end
    if f > t0 + PLAY then start_step(f) end
  elseif phase == "clearing" then
    if f == t0 + 300 then mark(f, string.format("clear%d_a", st.stage)) end
    if f == t0 + 300 then mark(f, string.format("clear%d_b", st.stage)) end
    if f > t0 + 1200 then start_step(f) end
  elseif phase == "ending" then
    if (f - t0) % 1500 == 800 then mark(f, string.format("ending_%05d", f - t0)) end
    if f > t0 + 12000 then start_step(f) end
  elseif phase == "gameover" then
    if f == t0 + 400 then mark(f, "gameover") end
    if f > t0 + 2500 then start_step(f) end
  end
  if FRAMES == 0 then FRAMES = f end
end

PICK_INPUT = function(f)
  if phase == "boot" or phase == "clearing" or phase == "gameover" then
    return {start = f % 90 < 4, a = false}
  end
  if phase == "ending" then return {} end
  -- The world map waits for a button; holding one in the stage does no harm.
  if phase == "dying" then return {start = f % 90 < 4} end
  if phase == "play" and f - t0 < 300 and r(0x4A) == 0 then return {start = f % 90 < 4} end
  local beat = (f - t0) % 400
  return {right = beat < 300, left = beat >= 310 and beat < 390,
          a = f % 53 < 20, b = f % 150 < 60, up = f % 700 < 30, down = f % 900 < 20}
end
