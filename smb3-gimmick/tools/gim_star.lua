local OUT="/home/olof/dev/romhacks/smb3-gimmick/out/"
local M=emu.memType.nesMemory
local function r(a) return emu.read(a,M) end
local f=0
emu.addEventCallback(function()
  local inp={}
  if f<560 and r(0x90)==0 then inp.start=(f%60)<5 end
  if f>=700 and f<760 then inp.b=true end
  emu.setInput(inp,0)
end, emu.eventType.inputPolled)
local h=io.open(OUT.."gim_star.txt","w")
emu.addEventCallback(function()
  f=f+1
  if (f>=700 and f<=790 and f%3==0) then
    local s=string.format("f=%d st1=%02x anim1=%02x banks=%02x %02x %02x %02x px=%02x%02x py=%02x%02x sx=%02x%02x sy=%02x%02x scroll=%02x%02x oam",f,r(0x91),r(0x301),r(0xe1),r(0xe2),r(0xe3),r(0xe4),r(0xb8),r(0xae),r(0xa4),r(0x9a),r(0xb9),r(0xaf),r(0xa5),r(0x9b),r(0x15),r(0x14))
    for i=0,255,4 do
      local y=emu.read(i,emu.memType.nesSpriteRam)
      if y<0xef then s=s..string.format(" [%02x %02x %02x %02x]",y,emu.read(i+1,emu.memType.nesSpriteRam),emu.read(i+2,emu.memType.nesSpriteRam),emu.read(i+3,emu.memType.nesSpriteRam)) end
    end
    h:write(s.."\n")
  end
  if f==730 or f==761 or f==775 then local g=io.open(OUT..string.format("gs_%d.png",f),"wb"); g:write(emu.takeScreenshot()); g:close() end
  if f==800 then h:close(); emu.stop(0) end
end, emu.eventType.endFrame)
