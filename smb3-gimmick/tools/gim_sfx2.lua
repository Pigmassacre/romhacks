local OUT="/home/olof/dev/smb3-gimmick/out/"
local M=emu.memType.nesMemory
local function r(a) return emu.read(a,M) end
local f=0
local log=io.open(OUT.."gim_sfx2.log","w")
local ids={0x0d,0x0f,0x10,0x13,0x15,0x17}
local reg={}
local sel=0
emu.addEventCallback(function()
  local inp={}
  if f<560 and r(0x90)==0 then inp.start=(f%60)<5 end
  emu.setInput(inp,0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  local y=emu.getState()["cpu.y"]
  if r(0x56+y)==0x06 then emu.write(0x56+y,0x00,M) end
end, emu.callbackType.exec, 0xF28C, 0xF28C)
emu.addMemoryCallback(function(a,v)
  if a<0xE000 then sel=v else reg[sel]=v end
end, emu.callbackType.write, 0xC000, 0xFFFF)
local cur=nil
emu.addEventCallback(function()
  f=f+1
  if f>=700 and (f-700)%120==0 then
    local i=(f-700)//120+1
    if ids[i] then
      local n=r(0x5a)
      emu.write(0x56+n,ids[i],M) emu.write(0x5a,n+1,M)
      cur=ids[i]
      log:write(string.format("ID %02x\n",cur))
    else
      log:close() emu.stop(0)
    end
  end
  if cur then
    log:write(string.format("%d C=%03x v=%02x mix=%02x np=%02x\n",f,(reg[5] or 0)*256+(reg[4] or 0),reg[10] or 0,reg[7] or 0,reg[6] or 0))
  end
end, emu.eventType.endFrame)
