dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
local died=nil
emu.addMemoryCallback(function() if not died then died=F log("DIE f="..F) end end, emu.callbackType.exec, S["Player_Die"], S["Player_Die"])
emu.addMemoryCallback(function(a,v)
  if died then log(string.format("%d W %04x=%02x",F-died,a,v)) end
end, emu.callbackType.write, 0x4000, 0x400F)
FRAME=function(f)
  if f==10 then ws("Level_TimerMSD",0,0) ws("Level_TimerMid",0,0) ws("Level_TimerLSD",0,0) end
  if died and f-died==40 then shot("death_40.png") end
  if died and f-died==250 then quit() end
  if f>400 then log("no death") quit() end
end
