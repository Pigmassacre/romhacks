local OUT="/home/olof/dev/smb3-gimmick/out/"
local M=emu.memType.nesMemory
local function r(a) return emu.read(a,M) end
local f=0
local log=io.open(OUT.."gim_sfx.log","w")
local script={
 {860,862,{a=true}},
 {1000,1100,{}},
 {1100,1170,{b=true}},
 {1240,1300,{b=true,right=true}},
}
emu.addEventCallback(function()
  local inp={}
  if f<560 and r(0x90)==0 then inp.start=(f%60)<5 end
  for _,s in ipairs(script) do if f>=s[1] and f<s[2] then for k,v in pairs(s[3]) do inp[k]=v end end end
  emu.setInput(inp,0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  local st=emu.getState()
  log:write(string.format("%d SFX a=%02x\n",f,st["cpu.a"]))
end, emu.callbackType.exec, 0xF285, 0xF285)
emu.addMemoryCallback(function()
  local y=emu.getState()["cpu.y"]
  if r(0x56+y)==0x06 then emu.write(0x56+y,0x00,M) end
end, emu.callbackType.exec, 0xF28C, 0xF28C)
emu.addMemoryCallback(function(a,v)
  if f<650 then return end
  log:write(string.format("%d W %04x=%02x\n",f,a,v))
end, emu.callbackType.write, 0x4000, 0x4017)
emu.addMemoryCallback(function(a,v)
  if f<650 then return end
  log:write(string.format("%d 5B %04x=%02x\n",f,a,v))
end, emu.callbackType.write, 0xC000, 0xFFFF)
emu.addEventCallback(function()
  f=f+1
  if f==1400 then log:close() emu.stop(0) end
end, emu.eventType.endFrame)
