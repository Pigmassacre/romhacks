local OUT="/home/olof/dev/romhacks/smb3-gimmick/out/"
local f=0
local function shot(name)
  local h=io.open(OUT..name..".png","wb"); h:write(emu.takeScreenshot()); h:close()
end
emu.addEventCallback(function()
  local fr=emu.getState()["ppu.frameCount"] or f
  local pressStart = (f%60)<5 and f<1500
  emu.setInput({start=pressStart}, 0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  f=f+1
  if f%150==0 then shot(string.format("gb_%04d",f)); emu.log(string.format("f=%d st=%02x x=%02x:%02x y=%02x:%02x lvl=%02x",f,emu.read(0x90,emu.memType.nesMemory),emu.read(0xB8,emu.memType.nesMemory),emu.read(0xAE,emu.memType.nesMemory),emu.read(0xA4,emu.memType.nesMemory),emu.read(0x9A,emu.memType.nesMemory),emu.read(0x1B,emu.memType.nesMemory))) end
  if f==1800 then emu.stop(0) end
end, emu.eventType.endFrame)
