local OUT="/home/olof/dev/smb3-gimmick/out/"
local f=0
local function shot(name)
  local h=io.open(OUT..name..".png","wb"); h:write(emu.takeScreenshot()); h:close()
end
emu.addEventCallback(function()
  emu.setInput({start=(f>=1500 and f<1505)},0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  f=f+1
  if f%100==0 then shot(string.format("ti_%04d",f)) end
  if f==1700 then emu.stop(0) end
end, emu.eventType.endFrame)
