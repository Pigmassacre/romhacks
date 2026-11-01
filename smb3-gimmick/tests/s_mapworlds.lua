-- Each world's map, with the Player's sprites close up, for looking over.
local base, w_, phase = nil, 0, "boot"
INPUT = function(f)
  if phase == "boot" then
    if f >= 120 and f < 125 then return {start = true} end
    if f >= 200 and f < 205 then return {start = true} end
    return {}
  end
  return {}
end
local function nextw()
  if w_ > 7 then done(); return end
  onexec(function() emu.loadSavestate(base); F = 0; ws("World_Num", w_); phase = "wait" end)
end
FRAME = function(f)
  if phase == "boot" then
    if f == 210 then phase = "saving"; onexec(function() base = emu.createSavestate(); nextw() end) end
    return
  end
  if phase == "wait" then
    local o = ""
    if f == 700 or f == 708 or f == 716 or f == 724 then
      shot(string.format("%d_%d", w_ + 1, f))
    end
    if f == 716 then
      for i = 0x84, 0x93, 4 do o = o .. string.format(" [%02x %02x %02x %02x]", r(0x200 + i), r(0x201 + i), r(0x202 + i), r(0x203 + i)) end
      local p = ""; for k = 16, 31 do p = p .. string.format(" %02x", emu.read(k, emu.memType.nesPaletteRam)) end
      log(string.format("world %d%s |%s", w_ + 1, o, p))
    end
    if f == 730 then w_ = w_ + 1; nextw() end
  end
end
