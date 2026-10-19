dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,dx,dy,dur=P:match("(%S+) (%-?%d+) (%-?%d+) (%d+)")
dx=tonumber(dx) dy=tonumber(dy) dur=tonumber(dur)
loadstate(OUT.."lv_"..name..".mss")
FRAME=function(f)
  if f>=10 and f<10+dur then
    local x=rs("Player_XHi")*256+rs("Player_X")+dx
    local y=rs("Player_YHi")*256+rs("Player_Y")+dy
    ws("Player_X",0,x%256) ws("Player_XHi",0,x>>8)
    ws("Player_Y",0,y%256) ws("Player_YHi",0,y>>8)
    ws("Player_YVel",0,0) ws("Player_XVel",0,0)
  end
  if f%10==0 then log(string.format("f=%d px=%d py=%d vs=%d air=%d hp=%d dying=%d",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),rs("Vert_Scroll_Hi")*256+rs("Vert_Scroll"),rs("Player_InAir"),rs("Gim_Health"),rs("Player_IsDying"))) end
  if f%50==0 then shot(string.format("fly_%s_%04d.png",name,f)) end
  if f>=dur+80 then quit() end
end
