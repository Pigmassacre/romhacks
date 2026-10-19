local OUT="/home/olof/dev/smb3-gimmick/out/"
local M=emu.memType.nesMemory
local function r(a) return emu.read(a,M) end
local f=0
emu.addEventCallback(function()
  local inp={}
  if f<560 and r(0x90)==0 then inp.start=(f%60)<5 end
  emu.setInput(inp,0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  f=f+1
  if f==900 then
    local h=io.open(OUT.."gim_ppu.txt","w")
    local s="pal"
    for i=0,31 do s=s..string.format(" %02x",emu.read(i,emu.memType.nesPaletteRam)) end
    h:write(s.."\n")
    s="banks"
    for i=0xe1,0xe8 do s=s..string.format(" %02x",r(i)) end
    h:write(s.."\n")
    s="oam"
    for i=0,255 do s=s..string.format(" %02x",emu.read(i,emu.memType.nesSpriteRam)) end
    h:write(s.."\n")
    h:write(string.format("player x=%02x%02x y=%02x%02x anim=%02x\n",r(0xb8),r(0xae),r(0xa4),r(0x9a),r(0x300)))
    h:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
