-- Not a test: instructions executed in the hack bank, per routine (label),
-- over 300 frames from the castle savestate.
local counts = {}
local on = false
emu.addMemoryCallback(function(a)
  if on and r(0x1BE) > 0 then
    if a >= 0xC000 then a = 0x10000 + (a & 0xFF00) end   -- fixed bank: by page
    counts[a] = (counts[a] or 0) + 1
  end
end, emu.callbackType.exec, 0x8000, 0xFFFF)
local labels = {}
for line in io.lines(REPO .. "/out/symbols.txt") do
  local n, v = line:match("^(%S+) = %$(%x+)")
  if n then labels[#labels + 1] = {tonumber(v, 16), n} end
end
table.sort(labels, function(a, b) return a[1] < b[1] end)
loadstate_raw("castle", function() on = true end)
INPUT = function(f)
  local p = f % 60
  return {right = p < 40, b = p % 6 == 0, a = p > 45 and p < 50}
end
FRAME = function(f)
  if f == 300 then
    local per = {}
    for a, c in pairs(counts) do
      local best = nil
      if a >= 0x10000 then best = string.format("fixed $%04X page", a & 0xFFFF) end
      if not best then for _, l in ipairs(labels) do if l[1] <= a and l[1] >= 0x8000 and l[1] < 0xC000 then best = l[2] else if l[1] > a then break end end end end
      per[best or "?"] = (per[best or "?"] or 0) + c
    end
    local t = {}
    for k, v in pairs(per) do t[#t + 1] = {k, v} end
    table.sort(t, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(25, #t) do log(string.format("%-28s %6d instructions a frame", t[i][1], t[i][2] // 300)) end
    log("PASS"); done()
  end
end
