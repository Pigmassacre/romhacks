-- Record Metroid's sound effects as APU writes, frame by frame.
-- Run with tools/lua.py tools/record_sfx.lua Metroid.nes; writes out/lua/sfx.txt.
-- Each effect is started by setting its init flag (Metroid's SFX*InitFlags),
-- and recorded until its continue flag clears.
local SFX = {
  -- name, init flags address, bit, continue flags address, registers
  {"Walk", 0x680, 0x08, 0x688, 0x0C, 0x0F},
  {"MissileLaunch", 0x680, 0x20, 0x688, 0x0C, 0x0F},
  {"Jump", 0x681, 0x02, 0x689, 0x00, 0x03},
  {"BulletFire", 0x681, 0x10, 0x689, 0x00, 0x03},
  {"EnemyHit", 0x681, 0x04, 0x689, 0x00, 0x03},
  {"EnergyPickup", 0x681, 0x40, 0x689, 0x00, 0x03},
  {"MissilePickup", 0x681, 0x80, 0x689, 0x00, 0x03},
  {"Die", 0x683, 0x80, 0x68B, 0x08, 0x0B},
  {"Ball", 0x683, 0x02, 0x68B, 0x08, 0x0B},
  {"Beep", 0x683, 0x08, 0x68B, 0x08, 0x0B},
  {"Hit", 0x684, 0x04, 0x68C, 0x00, 0x07},
  {"BombLaunch", 0x683, 0x01, 0x68B, 0x08, 0x0B},
  {"BombExplode", 0x680, 0x10, 0x688, 0x0C, 0x0F},
}
local out = io.open(OUT .. "sfx.txt", "w")
local cur, curFrame, state, wait, idx = nil, 0, "boot", 0, 1
local frameWrites = {}
emu.addMemoryCallback(function(a, v)
  if cur and a - 0x4000 >= cur[5] and a - 0x4000 <= cur[6] then
    frameWrites[#frameWrites + 1] = string.format("%x=%02x", a - 0x4000, v)
  end
end, emu.callbackType.write, 0x4000, 0x4013)
INPUT = function(f)
  if f < 400 then return {start = (f % 90) < 3 and f > 60} end
  return {}
end
FRAME = function(f)
  if state == "boot" then
    if f > 1200 then state = "idle"; wait = 30 end
    return
  end
  if state == "idle" then
    wait = wait - 1
    if wait > 0 then return end
    cur = SFX[idx]
    if not cur then out:close(); log("done"); stop(); return end
    w(cur[2], r(cur[2]) | cur[3])
    curFrame = 0
    frameWrites = {}
    state = "rec"
    out:write("sfx " .. cur[1] .. "\n")
    return
  end
  -- recording: this frame's writes
  out:write("  " .. table.concat(frameWrites, " ") .. "\n")
  frameWrites = {}
  curFrame = curFrame + 1
  if (curFrame > 2 and (r(cur[4]) & cur[3]) == 0) or curFrame > 400 then
    out:write("end\n")
    log(cur[1] .. " " .. curFrame .. " frames")
    cur = nil
    idx = idx + 1
    state = "idle"; wait = 40
  end
end
