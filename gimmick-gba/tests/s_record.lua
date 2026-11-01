-- Records a reference run of the NES game: what code runs, what the game reads
-- from the pad, and the whole of RAM at every NMI. tools/record.py runs this.
local OUT_DIR = OUT
FRAMES = FRAMES or 3000
M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end

local cov = {}
local nmi_now = 0
local started = false
local pads = io.open(OUT_DIR .. "pads.txt", "w")
local cpu = io.open(OUT_DIR .. "cpu.txt", "w")
local ram = io.open(OUT_DIR .. "ram.bin", "wb")

-- Where execution arrives other than from just after the last instruction: jump
-- targets, returns, and interrupts. The translator starts blocks at these.
local entries, last = {}, -1
local trace = TRACE_FROM and io.open(OUT_DIR .. "steps.txt", "w")
emu.addMemoryCallback(function(a, v)
  if not started then
    -- RAM at power-on is random, so the replay starts from the same values.
    started = true
    local h = io.open(OUT_DIR .. "poweron.bin", "wb")
    for i = 0, 0x7FF do h:write(string.char(emu.read(i, emu.memType.nesInternalRam))) end
    for i = 0, 0x1FFF do h:write(string.char(emu.read(i, emu.memType.nesWorkRam))) end
    h:close()
  end
  if trace and nmi_now >= TRACE_FROM and nmi_now <= TRACE_TO then
    local s = emu.getState()
    trace:write(string.format("%04X %02X %02X %02X %02X\n", a, s["cpu.a"], s["cpu.x"], s["cpu.y"], s["cpu.sp"]))
  end
  if a < last or a > last + 3 then entries[a] = true end
  last = a
  local c = emu.convertAddress(a, M)
  local k = (c and c.address or -1) * 65536 + a
  cov[k] = (cov[k] or 0) + 1
end, emu.callbackType.exec, 0x0000, 0xFFFF)

-- Every value the game gets from the pad ports, in order, so a replay needs no
-- timing. It is taken from A just after the reads at $F2D7 and $F2E0: a read
-- callback on the port also sees the extra reads that DPCM playback causes.
local pad_reads = io.open(OUT_DIR .. "padreads.bin", "wb")
local function pad_read()
  pad_reads:write(string.char(emu.getState()["cpu.a"]))
end
emu.addMemoryCallback(pad_read, emu.callbackType.exec, 0xF2DA, 0xF2DA)
emu.addMemoryCallback(pad_read, emu.callbackType.exec, 0xF2E3, 0xF2E3)

local nmi = 0
local apu_log = APU_LOG and io.open(OUT_DIR .. "apu.txt", "w")
-- A write the script makes to RAM, kept so the replay can make the same one.
local pokes = io.open(OUT_DIR .. "pokes.txt", "w")
function poke(a, v)
  emu.write(a, v, emu.memType.nesDebug)
  pokes:write(string.format("%d %d %d\n", nmi, a, v))
end
local function finish()
  local h = io.open(OUT_DIR .. "coverage.txt", "w")
  for k, n in pairs(cov) do
    h:write(string.format("%d %d %d\n", k // 65536, k % 65536, n))
  end
  h:close()
  h = io.open(OUT_DIR .. "entries.txt", "w")
  for a in pairs(entries) do h:write(a, "\n") end
  h:close()
  if trace then trace:close() end; if apu_log then apu_log:close() end; pokes:close(); pad_reads:close(); pads:close(); cpu:close(); ram:close()
  emu.stop(0)
end

emu.addMemoryCallback(function()
  nmi = nmi + 1
  nmi_now = nmi
  if ON_NMI then ON_NMI(nmi) end
  local s = emu.getState()
  if APU_LOG then
    -- The sound chips' state, for tools/compare_sound.py.
    local function pulse(n)
      local e = "apu.square" .. n .. ".envelope."
      local vol = s[e .. "constantVolume"] and s[e .. "volume"] or s[e .. "counter"]
      local on = s[e .. "lengthCounter.counter"] > 0
      return string.format("%d %d %d ", s["apu.square" .. n .. ".realPeriod"], on and vol or 0, s["apu.square" .. n .. ".duty"])
    end
    local e = "apu.noise.envelope."
    local t = "apu.triangle."
    local line = pulse(1) .. pulse(2) .. string.format("%d %d %d %d ", s[t .. "timer.period"],
      (s[t .. "lengthCounter.counter"] > 0 and s[t .. "linearCounter"] > 0) and 1 or 0,
      s["apu.noise.timer.period"] + 1,
      s[e .. "lengthCounter.counter"] > 0 and (s[e .. "constantVolume"] and s[e .. "volume"] or s[e .. "counter"]) or 0)
    for i = 0, 13 do line = line .. s["mapper.audio.registers" .. i] .. " " end
    apu_log:write(line, "\n")
  end
  cpu:write(string.format("%d %d %d %d %d %d %d\n", nmi, s["cpu.cycleCount"], s["cpu.a"], s["cpu.x"], s["cpu.y"], s["cpu.sp"], s["cpu.ps"]))
  local t = {}
  for a = 0x0000, 0x07FF do t[#t + 1] = string.char(r(a)) end
  for a = 0x6000, 0x7FFF do t[#t + 1] = string.char(r(a)) end
  ram:write(table.concat(t))
  if nmi >= FRAMES then finish() end
end, emu.callbackType.exec, 0xE9C6, 0xE9C6)

-- Scripted play: Start through the title, then run right with jumps and stars.
local polls = 0
local BITS = {a = 1, b = 2, select = 4, start = 8, up = 16, down = 32, left = 64, right = 128}
emu.addEventCallback(function()
  polls = polls + 1
  local f, inp = nmi, {}
  if PICK_INPUT then
    inp = PICK_INPUT(f)
  elseif IDLE then
    -- Nothing pressed: the title screen and whatever it leads to.
  elseif r(0x90) == 0 then
    inp.start = f % 60 < 5
  else
    local beat = f % 240
    inp.right = beat < 170
    inp.left = beat >= 200 and beat < 225
    inp.a = f % 47 < 14
    inp.b = f % 131 < 50
  end
  emu.setInput(inp, 0)
  local byte = 0
  for k, b in pairs(BITS) do if inp[k] then byte = byte | b end end
  pads:write(string.format("%d %d\n", nmi, byte))
end, emu.eventType.inputPolled)
