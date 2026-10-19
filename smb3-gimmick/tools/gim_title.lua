local OUT="/home/olof/dev/smb3-gimmick/out/"
local f=0
local function shot(name)
  local h=io.open(OUT..name..".png","wb"); h:write(emu.takeScreenshot()); h:close()
end
emu.addEventCallback(function()
  emu.setInput({start=(f>=400 and f<405)},0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  f=f+1
  if f==600 then shot(string.format("gt_%04d",f)) end
end, emu.eventType.endFrame)
emu.addEventCallback(function()
  if f==600 then
    local h=io.open(OUT.."gim_title.bin","wb")
    local t={}
    for a=0,0x2FFF do t[#t+1]=string.char(emu.read(a,emu.memType.nesPpuMemory)) end
    for a=0,31 do t[#t+1]=string.char(emu.read(a,emu.memType.nesPaletteRam)) end
    h:write(table.concat(t))
    h:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
