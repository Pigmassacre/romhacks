dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,x,y,vx,dx=P:match("(%S+) (%d+) (%d+) (%-?%d+) (%-?%d+)")
x=tonumber(x) y=tonumber(y) vx=tonumber(vx) dx=tonumber(dx)
loadstate(OUT.."lv_"..name..".mss")
local landed=nil
local minpy=99999
local rode=0
FRAME=function(f)
  ws("Gim_Health",0,3)
  if f==3 then
    ws("Player_X",0,x%256) ws("Player_XHi",0,x//256)
    ws("Player_Y",0,y%256) ws("Player_YHi",0,y//256)
    ws("Player_InAir",0,1) ws("Player_YVel",0,0) ws("Player_XVel",0,0)
  end
  local px=rs("Player_XHi")*256+rs("Player_X")
  local py=rs("Player_YHi")*256+rs("Player_Y")
  if f>3 and not landed and rs("Player_InAir")==0 then
    landed=f
    local sx=px+dx
    local sy=py+16-6
    ws("Star_State",0,1)
    ws("Star_X",0,sx%256) ws("Star_XHi",0,sx//256)
    ws("Star_Y",0,sy%256) ws("Star_YHi",0,sy//256)
    ws("Star_XVel",0,vx) ws("Star_YVel",0,0)
    ws("Star_SavedXVel",0,vx) ws("Star_SavedYVel",0,0)
    ws("Star_StillCnt",0,0) ws("Star_Floor",0,0) ws("Star_PrevFloor",0,0) ws("Star_Wall",0,0)
    ws("Star_Standable",0,1)
    log(string.format("landed f=%d px=%d py=%d",f,px,py))
  end
  if landed then
    if rs("Star_Ridden")~=0 then rode=rode+1 end
    log(string.format("f=%d px=%d py=%d air=%d rid=%d sx=%d sy=%d",f,px,py,rs("Player_InAir"),rs("Star_Ridden"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y")))
    if f==landed+40 then log("RIDDEN_FRAMES="..rode) quit() end
  end
  if f>300 then log("never landed") quit() end
end
