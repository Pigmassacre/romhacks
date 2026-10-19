local f=0
emu.addEventCallback(function()
  f=f+1
  if f==240 then
    local png=emu.takeScreenshot()
    local h=io.open("/home/olof/dev/smb3-gimmick/out/smoke.png","wb"); h:write(png); h:close()
    emu.log("done "..emu.read(0x00F5, emu.memType.nesMemory))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
