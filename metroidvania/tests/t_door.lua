-- Up the hall's last stairs and through the door at the top, into stage 2,
-- as Castlevania shows Simon: running up the steps (Castlevania moves him a
-- pixel every other frame, which once made Samus flicker between standing
-- and running), hidden while the screen scrolls to the door and it opens,
-- running through it, standing while the screen scrolls on, and the HUD
-- there all along, as Castlevania's status bar is.
local phase, t0 = "back", 0
local climb, stand, frames, hidden, shown, hud, still, walk, walkhid = 0, 0, {}, 0, 0, 0, 0, 0, 0
local function x() return r(0x122) + 256 * r(0x123) end
-- (Sprite RAM shows the frame before: a frame at each change of step
-- doesn't count.) Samus's sprites are the only ones with Simon's tiles ($00-$6F), past the HUD's (1-7)
local function samus_sprites()
  local n = 0
  for i = 8, 63 do
    local y = emu.read(i * 4, emu.memType.nesSpriteRam)
    local t = emu.read(i * 4 + 1, emu.memType.nesSpriteRam)
    if y < 0xEF and t < 0x70 then n = n + 1 end
  end
  return n
end
loadstate_raw("stairs1")
INPUT = function(f)
  if phase == "back" then return pad("L") end
  if phase == "up" then return (f % 2 == 0) and pad("U") or {} end
  if phase == "climb" then return pad("U") end
  if phase == "right" then return pad("R") end
  return {}
end
FRAME = function(f)
  w(0x5B, 0x40)                                   -- no zombies' hits
  local a, mode, aux = r(0x46C), r(0x18), r(0x19)
  if phase == "back" and x() < 0x50C then phase = "up" end
  if phase == "up" and (a == 6 or a == 4) then phase = "climb"; t0 = f end
  if phase == "climb" and a == 4 and f > t0 + 8 then
    climb = climb + 1
    frames[r(0x103)] = true
    if r(0x103) == 0x08 then stand = stand + 1 end
  end
  if phase == "climb" and a == 0 and r(0x354) < 0x70 then phase = "right" end
  if mode == 8 then
    if aux < 2 then
      if samus_sprites() == 0 then hidden = hidden + 1 else shown = shown + 1 end
    end
    if aux == 2 then
      walk = walk + 1
      if samus_sprites() == 0 then walkhid = walkhid + 1 end
    end
    if aux == 5 and r(0x103) ~= 0x08 then still = still + 1 end
    if emu.read(4, emu.memType.nesSpriteRam) == 0x19 then hud = hud + 1 end
    if phase ~= "door" then phase = "door"; t0 = f end
    if f == t0 + 60 then shot("door") end
  end
  if phase == "door" and mode == 5 and aux == 6 and r(0x28) == 2 then
    local n = 0
    for _ in pairs(frames) do n = n + 1 end
    check(climb > 100 and n >= 3, string.format("Samus runs up the stairs (%d frames, %d different)", climb, n))
    check(stand == 0, string.format("and never stands on them (%d frames did)", stand))
    check(hidden > 100 and shown <= 2, string.format("hidden while the screen scrolls to the door and it opens (%d frames; %d shown)", hidden, shown))
    check(walk > 50 and walkhid <= 2, string.format("drawn while walking through the door (%d of %d frames)", walk - walkhid, walk))
    check(still == 0, string.format("standing while the screen scrolls on (%d frames not)", still))
    check(hud > 300, string.format("the HUD is up through the door (%d frames)", hud))
    check(true, "in stage 2")
    done()
  end
  if f > 2000 then check(false, "through the door (" .. phase .. ")"); done() end
end
