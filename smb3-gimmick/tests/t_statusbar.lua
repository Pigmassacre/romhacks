-- The status bar's meter: health as glowing arrows, up to the maximum as dark ones, and the rest
-- blank, then the dark [P]'s two halves (the right half was once whatever X held). The map shows
-- the maximum: it once showed what the last level left, dark after a death.
local vr = function(a) return emu.read(a, emu.memType.nesPpuMemory) end
local function meter() local t = {}; for i = 0, 7 do t[#t + 1] = string.format("%02x", vr(0x2B28 + i)) end; return table.concat(t, " ") end
loadstate_raw("lv_W101L")
local phase = "level"
FRAME = function(f)
  if phase == "level" then
    if f == 5 then check(meter() == "ee ee ee fe fe fe 3c 3d", "3 of 3: " .. meter()); ws("Gim_MaxHealth", 5); ws("Gim_Health", 3) end
    if f == 10 then check(meter() == "ee ee ee ef ef fe 3c 3d", "3 of 5: " .. meter()); ws("Gim_MaxHealth", 3); ws("Gim_Health", 0)
      phase = "map"
      onexec(function()
        local h = io.open(OUT .. "map.mss", "rb"); local d = h:read("a"); h:close()
        emu.loadSavestate(d); F = 0
      end)
    end
  elseif f == 10 then
    check(meter() == "ee ee ee fe fe fe 3c 3d", "on the map, the maximum: " .. meter())
    done()
  end
end
