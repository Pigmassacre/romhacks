local OUT="/home/olof/dev/smb3-gimmick/out/"
local M=emu.memType.nesMemory
local function r(a) return emu.read(a,M) end
local f=0
local log=io.open(OUT.."gim_death.log","w")
local reg={}
local sel=0
emu.addEventCallback(function()
  local inp={}
  if f<560 and r(0x90)==0 then inp.start=(f%60)<5 end
  emu.setInput(inp,0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  log:write(string.format("%d SFX a=%02x\n",f,emu.getState()["cpu.a"]))
end, emu.callbackType.exec, 0xF285, 0xF285)
emu.addMemoryCallback(function(a,v)
  if a<0xE000 then sel=v else reg[sel]=v end
end, emu.callbackType.write, 0xC000, 0xFFFF)
emu.addMemoryCallback(function(a,v)
  if f>=695 then log:write(string.format("%d W %04x=%02x\n",f,a,v)) end
end, emu.callbackType.write, 0x4000, 0x4013)
emu.addEventCallback(function()
  f=f+1
  if f==700 then emu.write(0x0346,0,M) end
  if f>=695 then
    log:write(string.format("%d st=%02x A=%03x B=%03x C=%03x vol=%02x,%02x,%02x mix=%02x np=%02x\n",f,r(0x90),
      (reg[1] or 0)*256+(reg[0] or 0),(reg[3] or 0)*256+(reg[2] or 0),(reg[5] or 0)*256+(reg[4] or 0),
      reg[8] or 0,reg[9] or 0,reg[10] or 0,reg[7] or 0,reg[6] or 0))
  end
  if f==700 or f==720 or f==760 or f==820 then local h=io.open(OUT..string.format("gd_%d.png",f),"wb"); h:write(emu.takeScreenshot()); h:close() end
  if f==1000 then log:close() emu.stop(0) end
end, emu.eventType.endFrame)
