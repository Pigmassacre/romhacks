dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
local P=io.open(OUT.."param.txt"):read("l")
local walk,jump,rel=P:match("(%d+) (%d+) (%d+)")
walk,jump,rel=tonumber(walk),tonumber(jump),tonumber(rel)
INPUT=function(f)
  local t={}
  if f>=5 and f<walk then t.right=true end
  if f>=5 and f<rel then t.b=true end
  if f>=jump and f<jump+20 then t.a=true end
  return t
end
FRAME=function(f)
  local s=""
  for i=0,7 do if rs("Objects_State",i)~=0 then s=s..string.format(" %02x/%d@%d,%d",rs("Level_ObjectID",i),rs("Objects_State",i),rs("Objects_XHi",i)*256+rs("Objects_X",i),rs("Objects_YHi",i)*256+rs("Objects_Y",i)) end end
  log(string.format("f=%d px=%d py=%d st=%02x sx=%d sy=%d bounce=%d%s",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y"),rs("Player_Bounce"),s))
  if f==rel+12 or f==rel+40 then shot(string.format("b_%03d.png",f)) end
  if f==rel+60 then quit() end
end
