-- Dying each of the three ways: the music stops, Gimmick!'s jingle plays through, a life goes,
-- and the map's music is playing back on the map, with health full again at the next level.
local how, phase, t = 1, "run", 0
local WAYS = {"enemy", "pit", "time"}
local jingleEnd, lives
local base
local function start()
  phase = "run"; t = 0; jingleEnd = nil
  onexec(function()
    local h = io.open(OUT .. "lv_W101L.mss", "rb"); local d = h:read("a"); h:close()
    emu.loadSavestate(d); F = 0
  end)
end
start()
FRAME = function(f)
  t = t + 1
  if phase == "run" then
    if f == 1 then lives = rs("Player_Lives") end
    if f == 3 then
      local way = WAYS[how]
      if way == "enemy" then
        ws("Gim_Health", 1); local x = px() + 8
        ws("Level_ObjectID", 0x72, 4); ws("Objects_State", 1, 4); ws("Objects_X", x, 4); ws("Objects_XHi", x // 256, 4)
        ws("Objects_Y", py() + 16, 4); ws("Objects_YHi", (py() + 16) // 256, 4); ws("Objects_SpawnIdx", 0xFF, 4)
      elseif way == "pit" then sety(py() + 40); ws("Player_YVel", 40); ws("Player_InAir", 1); w(S["Level_Tile_GndL"], 0)
      else ws("Level_TimerMSD", 0); ws("Level_TimerMid", 0); ws("Level_TimerLSD", 1) end
    end
    if rs("Gim_DeathPtrH") ~= 0 and not jingleEnd then jingleEnd = 0 end
    if jingleEnd == 0 and rs("Gim_DeathPtrH") == 0 then jingleEnd = f end
    if rs("Level_Tileset") == 0 and f > 30 then phase = "map"; t = 0
      log(string.format("%s: at the map after %d frames, jingle over at %s", WAYS[how], f, tostring(jingleEnd)))
    end
    if f > 2000 then check(false, WAYS[how] .. ": never back at the map, die " .. rs("Player_IsDying") .. " y " .. py()); done() end
  elseif phase == "map" and t == 120 then
    check(jingleEnd and jingleEnd > 0, WAYS[how] .. ": the jingle played through")
    check(rs("Player_Lives") == lives - 1, WAYS[how] .. ": a life gone")
    check(rs("SndCur_Music2") ~= 0, WAYS[how] .. ": map music playing: " .. rs("SndCur_Music2"))
    shot(WAYS[how])
    how = how + 1
    if how > #WAYS then done() else start() end
  end
end
