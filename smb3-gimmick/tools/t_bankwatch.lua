dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,frames,mode=P:match("(%S+) (%d+) (%S+)")
frames=tonumber(frames)
loadstate(OUT.."lv_"..name..".mss")
local last={}
emu.addMemoryCallback(function(addr,val)
  local pc=emu.getState()["cpu.pc"]
  local key=pc*256+val
  if not last[key] then
    last[key]=true
    log(string.format("f=%d pc=%04X val=%02X x=%d",F,pc,val,rs("Player_XHi")*256+rs("Player_X")))
  end
end, emu.callbackType.write, S["PatTable_BankSel"]+4, S["PatTable_BankSel"]+4)
INPUT=function(f)
  if f<2 then return {} end
  local t={right=true,a=(f%50)<20}
  if mode=="star" then t.b=(f%40)<25 end
  return t
end
FRAME=function(f)
  ws("Player_FlashInv",0,0x10)
  if f>=frames then quit() end
end
