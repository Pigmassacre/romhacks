dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
local w={}
emu.addMemoryCallback(function(a,v)
  w[#w+1]=string.format("%x=%02x",a-0x4000,v)
end, emu.callbackType.write, 0x4000, 0x4003)
INPUT=function(f)
  if f>=10 and f<14 then return {a=true} end
  if f>=60 and f<130 then return {b=true} end
  return {}
end
FRAME=function(f)
  log(string.format("f=%d pos=%d cur=%02x st=%02x | %s",f,rs("Gim_SndPos"),rs("SndCur_Player"),rs("Star_State"),table.concat(w," ")))
  w={}
  if f>=260 then quit() end
end
