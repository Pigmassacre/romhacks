-- Survey sound effects: which channels each one writes and for how long.
-- Not a pass/fail test; read out/test/sfx.log.
IDS = {0x13, 0x10, 0x15, 0x0d, 0x0f, 0x14, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1c, 0x1e, 0x12, 0x44, 0x08, 0x09, 0x0a}
REGV = {}
local cur, start, chans, frames, last5b = nil, 0, {}, {}, nil
local function note(ch, f) chans[ch] = true; frames[f] = true end
emu.addMemoryCallback(function(a, v)
  if cur == nil then return end
  local ch = ({[0]="sq1","sq1","sq1","sq1","sq2","sq2","sq2","sq2","tri","tri","tri","tri","noi","noi","noi","noi","dmc","dmc","dmc","dmc"})[a - 0x4000]
  if ch and REGV[a] ~= v then note(ch, GF) end
  REGV[a] = v
end, emu.callbackType.write, 0x4000, 0x4013)
emu.addMemoryCallback(function(a, v)
  if cur == nil then return end
  if a < 0xE000 then last5b = v; return end
  if last5b == nil or REGV[0x100 + last5b] == v then return end
  REGV[0x100 + last5b] = v
  note("5b" .. (({[0]="A","A","B","B","C","C","N","M","A","B","C","E","E","E"})[last5b] or "?"), GF)
end, emu.callbackType.write, 0xC000, 0xFFFF)
local idx = 0
FRAME = function(f)
  GF = f
  if f == 5 then w(0x56 + r(0x5A), 0x1F); w(0x5A, r(0x5A) + 1) end  -- stop the music
  if f < 80 then return end
  if f % 60 == 10 then w(0x56 + r(0x5A), 0x1F); w(0x5A, r(0x5A) + 1) end
  if f % 60 == 20 then
    if cur then
      local cs = {}
      for k in pairs(chans) do cs[#cs+1] = k end
      table.sort(cs)
      local n, lastf = 0, 0
      for k in pairs(frames) do n = n + 1; if k > lastf then lastf = k end end
      log(string.format("sfx %02x: frames=%d span=%d chans=%s", cur, n, lastf - start, table.concat(cs, ",")))
    end
    idx = idx + 1
    if idx > #IDS then done() return end
    cur = IDS[idx]; start = f; chans = {}; frames = {}
    local wi = r(0x5A)
    w(0x56 + wi, cur); if wi < 3 then w(0x5A, wi + 1) end
  end
end
