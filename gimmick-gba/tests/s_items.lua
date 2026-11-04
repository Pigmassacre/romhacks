-- Every item, in every stage, for tools/record.py --items: the fireball, the bomb and
-- the medicine, charged and thrown while walking both ways and jumping, at the first two
-- checkpoints of each stage (at the third of the first stage, Yumetaro starts held by a
-- crane and can do nothing), so the code they run is translated rather than left to the
-- interpreter. It warps by writing RAM like the tour: a death only goes back to a
-- checkpoint of the stage it is in, so each stage is reached by clearing the one before,
-- and the secret stage by clearing stage 6 with the treasures. Goes before s_record.lua.
FRAMES = 2000000
local PER_ITEM = 600
local ITEMS = {2, 3, 1}  -- $36: 1 medicine, 2 fireball, 3 bomb
local steps = {}
for stage = 0, 6 do
  if stage > 0 then steps[#steps + 1] = {kind = "clear", stage = stage - 1, treasures = stage == 6} end
  for _, cp in ipairs({0, 1}) do steps[#steps + 1] = {kind = "warp", stage = stage, cp = cp} end
end

local i, phase, t0, left = 0, "boot", 0, false
local marks = io.open(OUT .. "items.txt", "w")
local function shot(what)
  local h = io.open(OUT .. "shot_" .. what .. ".png", "wb")
  h:write(emu.takeScreenshot()); h:close()
end
local function start_step(f)
  i = i + 1
  t0 = f
  local st = steps[i]
  if not st then
    marks:close()
    FRAMES = 0
    return
  end
  if st.kind == "warp" then
    poke(0x1B, st.stage); poke(0x1C, st.cp); poke(0x346, 0); poke(0x104, 9)
    phase = "dying"
  else
    poke(0x1B, st.stage); poke(0xEB, 1); poke(0xEA, 1); poke(0x104, 9)
    if st.treasures then
      for a = 0x105, 0x10A do poke(a, 1) end
    end
    phase = "clearing"
    left = false
  end
end

local function on_map() return r(0x40) == 0x1C or r(0x40) == 0x1B end
local function in_stage() return r(0x90) == 1 and not on_map() end
local function item_now(f) return ITEMS[math.floor((f - t0) / PER_ITEM) + 1] end

ON_NMI = function(f)
  local st = steps[i]
  if phase == "boot" then
    if r(0x90) == 1 and f > 600 then start_step(f) end
  elseif phase == "dying" then
    if in_stage() and f > t0 + 60 then
      phase = "play"; t0 = f
      marks:write(f, string.format(" s%d_c%d\n", st.stage, st.cp)); marks:flush()
    elseif f > t0 + 1500 then
      marks:write(f, string.format(" stuck s%d_c%d\n", st.stage, st.cp)); marks:flush()
      start_step(f)
    end
  elseif phase == "clearing" then
    -- Out of the stage, through the map, and into the next.
    if not in_stage() then left = true end
    if (left and in_stage()) or f > t0 + 4000 then
      if not left then marks:write(f, string.format(" stuck clearing s%d\n", st.stage)); marks:flush() end
      start_step(f)
    end
  elseif phase == "play" then
    local item = item_now(f)
    if not item then
      start_step(f)
    else
      local beat = (f - t0) % 200
      -- The medicine only does something below the most health ($2B), so it is used
      -- at 1; otherwise health is kept at its most, not above it (see s_boss.lua).
      if item == 1 and beat == 0 then
        poke(0x346, 1)
      elseif r(0x346) < r(0x2B) and (item ~= 1 or beat > 150) then
        poke(0x346, r(0x2B))
      end
      if r(0x36) ~= item then poke(0x36, item) end
      if (f - t0) % PER_ITEM == 300 then shot(string.format("s%d_c%d_item%d", st.stage, st.cp, item)) end
    end
  end
  if FRAMES == 0 or f > 150000 then FRAMES = f end
end

-- In each 200 frames: charge walking right and throw, jump while charging and throw
-- in the air, then charge walking left and throw.
PICK_INPUT = function(f)
  if phase ~= "play" then
    return {start = (r(0x90) == 0 or r(0x90) >= 0xD0 or on_map()) and f % 60 < 5}
  end
  local beat = (f - t0) % 200
  local charge = (beat >= 10 and beat < 60) or (beat >= 75 and beat < 115) or (beat >= 130 and beat < 185)
  return {right = beat < 70, left = beat >= 125 and beat < 195,
          up = charge, b = charge, a = beat >= 85 and beat < 105}
end
