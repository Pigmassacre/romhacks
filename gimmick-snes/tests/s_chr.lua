-- How the game uses CHR pages and the PPU, frame by frame. tools/survey.py --chr.
M = emu.memType.nesMemory
function r(a) return emu.read(a, M) end
function poke(a, v) emu.write(a, v, emu.memType.nesDebug) end
local cmd, chr = 0, {[0]=0,0,0,0,0,0,0,0}
local nmi, in_vbl = 0, false
local ctrl_hist, mirror_hist = {}, {}
local changes = {}  -- slot -> list
local log = io.open(OUT .. "chr_frames.txt", "w")
local frame_changes, splitwrites = {}, 0
local ctrl = 0
local b = {[9]=0,[10]=0,[11]=0}
local combos = {}
emu.addMemoryCallback(function(a, v)
  if a < 0xA000 then cmd = v & 15
  elseif a < 0xC000 then
    if cmd < 8 then
      if chr[cmd] ~= v then frame_changes[#frame_changes + 1] = cmd .. ":" .. v; chr[cmd] = v end
    elseif cmd >= 9 and cmd <= 11 then
      b[cmd] = v
      local k = b[9] * 65536 + b[10] * 256 + b[11]
      combos[k] = (combos[k] or 0) + 1
    elseif cmd == 12 then mirror_hist[v & 3] = (mirror_hist[v & 3] or 0) + 1 end
  end
end, emu.callbackType.write, 0x8000, 0xBFFF)
emu.addMemoryCallback(function(a, v)
  if a % 8 == 0 then ctrl = v; ctrl_hist[v] = (ctrl_hist[v] or 0) + 1 end
end, emu.callbackType.write, 0x2000, 0x3FFF)
emu.addMemoryCallback(function()
  nmi = nmi + 1
  if #frame_changes > 0 then
    log:write(nmi, " ", ctrl, " ", table.concat(frame_changes, ","), "\n")
    frame_changes = {}
  end
  if ON_NMI then ON_NMI(nmi) end
  if FRAMES and nmi >= FRAMES then
    log:close()
    local h = io.open(OUT .. "ctrl.txt", "w")
    for k, n in pairs(ctrl_hist) do h:write(string.format("ctrl %02X %d\n", k, n)) end
    for k, n in pairs(mirror_hist) do h:write(string.format("mirror %d %d\n", k, n)) end
    for k, n in pairs(combos) do h:write(string.format("combo %06X %d\n", k, n)) end
    h:close()
    emu.stop(0)
  end
end, emu.callbackType.exec, 0xE9C6, 0xE9C6)
emu.addEventCallback(function() emu.setInput(PICK_INPUT and PICK_INPUT(nmi) or {}, 0) end, emu.eventType.inputPolled)
