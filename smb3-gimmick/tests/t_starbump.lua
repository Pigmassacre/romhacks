-- The star bumps what it hits: a ? block gives its item (and is used), and a brick breaks, from the
-- side and from below.
local CASES = {{"? block from the side", 0x60, 0, 0x19}, {"brick from the side", 0x67, 0, nil}, {"? block from below", 0x60, -1, 0x19}}
local i, phase = 1, "wait"
local function start()
  phase = "wait"
  onexec(function()
    local h = io.open(OUT .. "lv_W101L.mss", "rb"); local d = h:read("a"); h:close()
    emu.loadSavestate(d); F = 0; phase = "go"
  end)
end
start()
local addr, item
FRAME = function(f)
  if phase ~= "go" then return end
  local c = CASES[i]
  if f == 2 then
    local col, row = (px() + 56) // 16, (py() + 24) // 16
    if c[3] == -1 then
      col = (px() + 8) // 16; row = (py() - 24) // 16
      ws("Star_X", px()); ws("Star_XHi", 0); ws("Star_Y", py() + 8); ws("Star_YHi", (py() + 8) // 256); ws("Star_XVel", 0); ws("Star_YVel", -64)
    else
      ws("Star_X", px() + 16); ws("Star_XHi", 0); ws("Star_Y", (row * 16)); ws("Star_YHi", (row * 16) // 256); ws("Star_XVel", 40); ws("Star_YVel", 0)
    end
    addr = 0x6000 + (col // 16) * 0x1B0 + row * 16 + col % 16
    w(addr, c[2])
    ws("Star_State", 1); ws("Star_Standable", 0); ws("Star_Wall", 0); ws("Star_Floor", 0); ws("Star_StillCnt", 0)
    item = nil
  end
  for s = 0, 7 do if rs("Objects_State", s) ~= 0 and rs("Level_ObjectID", s) == 0x0D then item = 0x0D end; if rs("Objects_State", s) ~= 0 and rs("Level_ObjectID", s) == 0x19 then item = 0x19 end end
  if f == 60 then
    check(r(addr) ~= c[2], string.format("%s: the block changed to %02x", c[1], r(addr)))
    if c[4] then check(item == c[4], string.format("%s: gave %02x", c[1], item or 0)) end
    i = i + 1
    if i > #CASES then done() else start() end
  end
end
