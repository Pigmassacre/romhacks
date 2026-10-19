dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,obj,frames=P:match("(%S+) (%x+) (%d+)")
obj,frames=tonumber(obj,16),tonumber(frames)
loadstate(OUT.."lv_"..name..".mss")
local shots=0
INPUT=function(f)
  if f<2 then return {} end
  return {right=true,b=true,a=(f%50)<20}
end
FRAME=function(f)
  ws("Player_FlashInv",0,0x10)
  for i=0,4 do
    if rs("Level_ObjectID",i)==obj and rs("Objects_State",i)~=0 and f%6==0 and shots<12 then
      shots=shots+1
      shot(string.format("walk_%04d.png",f))
      log(string.format("f=%d x=%d slot=%d var7=%d",f,rs("Player_XHi")*256+rs("Player_X"),i,rs("Objects_Var7",i)))
      break
    end
  end
  if f>=frames or shots>=12 then quit() end
end
