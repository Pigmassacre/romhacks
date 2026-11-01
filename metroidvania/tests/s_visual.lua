-- Not a test of one thing: tests/s_play.lua's bot plays the game while this
-- watches what the screen would show, every frame, for out/test/visual.log:
--   TILE  a sprite the hack didn't draw using a tile Samus's graphics replaced
--   OVER  a sprite other than the HUD's on the status bar's lines
--   BG    a column of the stage that changed while on the screen (late loads,
--         wrong attributes; a broken block is one too)
--   PAL0  a sprite the hack didn't draw in Samus's colours (sprite palette 0)
--   PAL   each new set of palettes
-- and a line per stage of how often a line had more than 8 sprites.
-- VIS_SHOTS=n: a screenshot every n frames as well (play_'s are every 400).
dofile(REPO .. "/tests/s_play.lua")

local SP = emu.memType.nesSpriteRam
local PPU = emu.memType.nesPpuMemory
local PAL = emu.memType.nesPaletteRam
local PRG = emu.memType.nesPrgRom

local function symbol(name)
  for l in io.lines(REPO .. "/out/symbols.txt") do
    local v = l:match("^" .. name .. " = %$(%x+)")
    if v then return tonumber(v, 16) end
  end
end
local SPRITES_AT = symbol("Bank0_Sprites") + 9   -- after its FarCall
local NEXTOAM = symbol("NextOam")
local nextoam = function(o) return emu.read(0x20000 + NEXTOAM - 0x8000 + o, PRG) end

-- Tiles Samus's graphics replaced (src of the lists: tools/samus_gfx.py)
local TAKEN = {}
for t = 0x02, 0x3E, 2 do TAKEN[t] = true end
for _, t in ipairs({0x46, 0x48, 0x4C, 0x4E, 0x56, 0x58, 0x5E, 0x6A, 0x6C, 0x6E}) do TAKEN[t] = true end
for t = 0xD1, 0xFD, 2 do TAKEN[t] = true end

local hack = {}
emu.addMemoryCallback(function()
  if emu.read(SPRITES_AT, M) ~= 0xA9 or emu.read(SPRITES_AT + 2, M) ~= 0x2A then return end
  hack = {}
  local o, last = r(0x78), r(0x04)
  local guard = 0
  while o ~= last and guard < 64 do hack[o] = true; o = nextoam(o); guard = guard + 1 end
end, emu.callbackType.exec, SPRITES_AT, SPRITES_AT)

local playFrame = FRAME
local seen, columns, palettes, shots_n = {}, {}, {}, 0
local crowded, frames, crowdStage = 0, 0, nil
local dispLo, dispHi = 0, 0
local seenAt = {}
local EVERY = tonumber(os.getenv("VIS_SHOTS") or "0")

local function once(key, msg, tag)
  if seen[key] then return end
  seen[key] = true
  log(string.format("%s f %d stage %d mode %02x/%02x: %s", key:sub(1, 5), F, r(0x28), r(0x18), r(0x19), msg))
  if tag and shots_n < 150 then shots_n = shots_n + 1; shot(string.format("%s_%03d", tag, shots_n)) end
end

local function nearest(sx, sy)
  local best, bd
  for slot = 0, 0x1B do
    local d = math.abs(r(0x38C + slot) - sx) + math.abs(r(0x354 + slot) - sy)
    if (r(0x31C + slot) ~= 0 or r(0x434 + slot) ~= 0) and (not bd or d < bd) then best, bd = slot, d end
  end
  if not best then return "none" end
  return string.format("slot %02x ai %02x pose %02x type %02x", best, r(0x434 + best), r(0x31C + best), r(0x584 + best))
end

local function sprites()
  local mode = r(0x18)
  if mode <= 1 or mode == 3 or mode >= 0x0F then return end   -- the title, the ending: no Samus tiles
  local line = {}
  for i = 1, 63 do
    if i < 7 or i > 16 then
      local o = i * 4
      local y, t, a, sx = r(0x200 + o), r(0x201 + o), r(0x202 + o), r(0x203 + o)
      if y < 0xEF then
        local own = hack[o]
        if not own and TAKEN[t] then
          once(string.format("TILE %02x", t), string.format("sprite %d tile %02x at %02x,%02x attr %02x, near %s", i, t, sx, y, a, nearest(sx, y)), "tile")
        end
        if not own and (a & 3) == 0 and t > 1 then
          once(string.format("PAL0 %02x", t), string.format("sprite %d tile %02x at %02x,%02x attr %02x, near %s", i, t, sx, y, a, nearest(sx, y)), "pal0")
        end
        if y < 0x2C and (mode == 5 or mode == 2) and r(0x19) == 6 then
          once(string.format("OVER %s %02x", own and "samus" or "other", t), string.format("%s tile %02x at %02x,%02x, near %s", own and "hack" or "other", t, sx, y, nearest(sx, y)), "over")
        end
        for l = y + 1, math.min(y + 16, 239) do line[l] = (line[l] or 0) + 1 end
      end
    end
  end
  -- the HUD, sprites 7-16
  for i = 7, 16 do
    local y = r(0x200 + i * 4)
    if y < 0xEF then for l = y + 1, y + 16 do line[l] = (line[l] or 0) + 1 end end
  end
  for l = 1, 239 do if (line[l] or 0) > 8 then crowded = crowded + 1; break end end
  frames = frames + 1
end

-- A column of the name tables (0-63), with its 2-bit attributes.
local function column(hw)
  local nt = hw // 32
  local c = hw % 32
  local out = {}
  for row = 6, 29 do out[#out + 1] = emu.read(0x2000 + nt * 0x400 + row * 32 + c, PPU) end
  for row = 6, 29, 2 do
    local a = emu.read(0x23C0 + nt * 0x400 + (row // 4) * 8 + (c // 4), PPU)
    local q = ((row // 2) % 2) * 2 + ((c // 2) % 2)
    out[#out + 1] = (a >> (2 * q)) & 3
  end
  return out
end

-- The picture just shown came from the scroll the PPU was given; columns of the
-- stage are numbered from Castlevania's scroll, the PPU's are where they ended up
-- (which name table holds which screen differs by stage).
local function background(f)
  if not ((r(0x18) == 5 and r(0x19) == 6) or (r(0x18) == 2 and r(0x19) == 1)) then
    dispLo, dispHi = r(0x2E), r(0x2F)
    return
  end
  local c = emu.getState()
  local t = c["ppu.tmpVideoRamAddr"]
  local hw0 = (t & 0x1F) + (((t >> 10) & 1) * 32)
  local scroll = dispLo + 256 * dispHi
  local key0 = r(0x28) * 2 + r(0x46)
  local cols = columns[key0]
  if not cols then cols = {}; columns[key0] = cols end
  local first = scroll // 8
  local whole = f % 8 == 0
  for k = 0, 32 do
    if whole or k == 0 or k == 32 then
      local lc = first + k
      local now = column((hw0 + k) % 64)
      local was = cols[lc]
      if not was then cols[lc] = now; seenAt[key0 .. " " .. lc] = f
      else
        local tiles, attrs, sample = 0, 0, ""
        for i = 1, #now do
          if now[i] ~= was[i] then
            if i <= 24 then tiles = tiles + 1 else attrs = attrs + 1 end
            if sample == "" then sample = string.format("%s %d: %02x > %02x", i <= 24 and "row" or "attr row", i <= 24 and i + 5 or (i - 25) * 2 + 6, was[i], now[i]) end
          end
        end
        if tiles + attrs > 0 then
          local x8 = lc * 8 - scroll
          log(string.format("BG    f %d stage %d floor %d col %d at screen x %d, scroll %04x, first seen f %d: %d tiles %d attrs, %s", f, r(0x28), r(0x46), lc, x8, scroll, seenAt[key0 .. " " .. lc] or -1, tiles, attrs, sample))
          if x8 > 8 and x8 < 240 and tiles > 2 then once(string.format("BGMID %d %d", key0, lc), "mid-screen column change", "bg") end
          cols[lc] = now
        end
      end
    end
  end
  dispLo, dispHi = r(0x2E), r(0x2F)
end

local function palette()
  local t = {}
  for i = 0, 31 do t[#t + 1] = string.format("%02x", emu.read(i, PAL)) end
  local s = table.concat(t, " ")
  local key = r(0x28) .. " " .. s
  if not palettes[key] then
    palettes[key] = true
    log(string.format("PAL   f %d stage %d mode %02x/%02x: %s", F, r(0x28), r(0x18), r(0x19), s))
  end
end

-- When they go to the PPU: at the end of a frame, a late one is still drawing them.
emu.addMemoryCallback(function() pcall(sprites) end, emu.callbackType.write, 0x4014, 0x4014)

FRAME = function(f)
  playFrame(f)
  background(f)
  palette()
  if crowdStage ~= r(0x28) then
    if crowdStage then log(string.format("CROWD stage %d: %d of %d frames had a line over 8 sprites", crowdStage, crowded, frames)) end
    crowdStage = r(0x28); crowded = 0; frames = 0
  end
  if os.getenv("VIS_STOP") and f >= tonumber(os.getenv("VIS_STOP")) then log("PASS"); done(); return end
  if os.getenv("VIS_TRANS") and r(0x18) * 256 + r(0x19) ~= 0x506 and f % tonumber(os.getenv("VIS_TRANS")) == 0 then shot(string.format("t%07d_%02x%02x", f, r(0x18), r(0x19))) end
  -- (she blinks while the bot's invincible: on a frame she shows)
  if EVERY > 0 and f % EVERY < 2 and (r(0x1A) & 1) == 1 then shot(string.format("t%07d_%02d", f, r(0x28))) end
end
