-- Records what the translator has to know about the NES game: every bank combination
-- at $8000/$A000/$C000 and which of its windows were used, every access to hardware,
-- to $6000-$7FFF and to the mirrors of RAM, and all code that ran. tools/survey.py
-- runs this, with a script that plays the game before it.
M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function poke(a, v) emu.write(a, v, emu.memType.nesDebug) end

local cmd, b8, bA, bC, b6 = 0, 0, 0, 0, 0
local combo = 0
local touched, frames_in = {}, {}
local switches_this = 0
local switch_hist = {}
local pc = 0
local io_seen, w6_seen, mirror_seen, cov, entries, last = {}, {}, {}, {}, {}, -1
local w6_lo, w6_hi = 0xFFFF, 0

local function bank_of(a) local c = emu.convertAddress(a, M); return c and c.address or -1 end
local function set_combo()
  combo = b8 << 16 | bA << 8 | bC
end
local function touch(a)
  local bit = a < 0xA000 and 1 or a < 0xC000 and 2 or a < 0xE000 and 4 or 0
  if bit ~= 0 then touched[combo] = (touched[combo] or 0) | bit end
end

emu.addMemoryCallback(function(a)
  if a < last or a > last + 3 then entries[a] = true end
  last = a; pc = a
  if a >= 0x8000 then touch(a) end
  local k = bank_of(a) * 65536 + a
  cov[k] = (cov[k] or 0) + 1
  frames_in[combo] = (frames_in[combo] or 0) + 1
end, emu.callbackType.exec, 0x0000, 0xFFFF)

local function note_io(kind, a, v)
  local k = string.format("%s %d %04X %04X", kind, bank_of(pc), pc, a)
  io_seen[k] = (io_seen[k] or 0) + 1
end

emu.addMemoryCallback(function(a, v) if a ~= pc then touch(a) end end, emu.callbackType.read, 0x8000, 0xDFFF)
emu.addMemoryCallback(function(a, v) note_io("R", a) end, emu.callbackType.read, 0x2000, 0x5FFF)
emu.addMemoryCallback(function(a, v) note_io("W", a) end, emu.callbackType.write, 0x2000, 0x5FFF)
emu.addMemoryCallback(function(a, v) w6_lo = math.min(w6_lo, a); w6_hi = math.max(w6_hi, a); w6_seen[a] = true end, emu.callbackType.read, 0x6000, 0x7FFF)
emu.addMemoryCallback(function(a, v) w6_lo = math.min(w6_lo, a); w6_hi = math.max(w6_hi, a); w6_seen[a] = true end, emu.callbackType.write, 0x6000, 0x7FFF)
emu.addMemoryCallback(function(a, v) mirror_seen[pc * 65536 + a] = true end, emu.callbackType.read, 0x0800, 0x1FFF)
emu.addMemoryCallback(function(a, v) mirror_seen[pc * 65536 + a] = true end, emu.callbackType.write, 0x0800, 0x1FFF)
emu.addMemoryCallback(function(a, v)
  note_io("W", a)
  if a < 0xA000 then cmd = v & 15
  elseif a < 0xC000 then
    if cmd == 9 then b8 = v & 63 elseif cmd == 10 then bA = v & 63 elseif cmd == 11 then bC = v & 63
    elseif cmd == 8 then b6 = v; note_io("W6MAP" .. v, a) end
    if cmd >= 9 and cmd <= 11 then switches_this = switches_this + 1 end
    set_combo()
  end
end, emu.callbackType.write, 0x8000, 0xFFFF)

local nmi = 0
local function dump()
  local h = io.open(OUT .. "combos.txt", "w")
  for c, t in pairs(touched) do h:write(string.format("%06X %d %d\n", c, t, frames_in[c] or 0)) end
  h:close()
  h = io.open(OUT .. "io.txt", "w")
  for k, n in pairs(io_seen) do h:write(k, " ", n, "\n") end
  h:close()
  h = io.open(OUT .. "w6.txt", "w")
  h:write(string.format("range %04X %04X\n", w6_lo, w6_hi))
  local n = 0; for _ in pairs(w6_seen) do n = n + 1 end
  h:write("bytes ", n, "\n"); h:close()
  h = io.open(OUT .. "mirror.txt", "w")
  for k in pairs(mirror_seen) do h:write(string.format("%04X %04X\n", k // 65536, k % 65536)) end
  h:close()
  h = io.open(OUT .. "coverage.txt", "w")
  for k, n in pairs(cov) do h:write(string.format("%d %d %d\n", k // 65536, k % 65536, n)) end
  h:close()
  h = io.open(OUT .. "entries.txt", "w")
  for a in pairs(entries) do h:write(a, "\n") end
  h:close()
  h = io.open(OUT .. "switches.txt", "w")
  for s, c in pairs(switch_hist) do h:write(s, " ", c, "\n") end
  h:close()
end

emu.addMemoryCallback(function()
  nmi = nmi + 1
  switch_hist[switches_this] = (switch_hist[switches_this] or 0) + 1
  switches_this = 0
  if ON_NMI then ON_NMI(nmi) end
  if nmi % 2000 == 0 then dump() end
  if FRAMES and nmi >= FRAMES then dump(); emu.stop(0) end
end, emu.callbackType.exec, 0xE9C6, 0xE9C6)

local BITS = {a = 1, b = 2, select = 4, start = 8, up = 16, down = 32, left = 64, right = 128}
emu.addEventCallback(function()
  local inp = PICK_INPUT and PICK_INPUT(nmi) or {}
  emu.setInput(inp, 0)
end, emu.eventType.inputPolled)
