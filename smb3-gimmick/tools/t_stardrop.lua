dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,x,y,vx,vy=P:match("(%S+) (%d+) (%d+) (%-?%d+) (%-?%d+)")
x=tonumber(x) y=tonumber(y) vx=tonumber(vx) vy=tonumber(vy)
loadstate(OUT.."lv_"..name..".mss")
FRAME=function(f)
  ws("Gim_Health",0,3)
  if f==3 then
    ws("Star_State",0,1)
    ws("Star_X",0,x%256) ws("Star_XHi",0,x//256)
    ws("Star_Y",0,y%256) ws("Star_YHi",0,y//256)
    ws("Star_XVel",0,vx) ws("Star_YVel",0,vy)
    ws("Star_SavedXVel",0,vx) ws("Star_SavedYVel",0,vy)
    ws("Star_StillCnt",0,0) ws("Star_Floor",0,0) ws("Star_PrevFloor",0,0) ws("Star_Wall",0,0)
  end
  if f>=3 then
    log(string.format("f=%d st=%d sx=%d sy=%d svx=%d svy=%d fl=%d os=%d",f,rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y"),(rs("Star_XVel")+128)%256-128,(rs("Star_YVel")+128)%256-128,rs("Star_Floor"),rs("Star_OnSlope")))
  end
  if f==8 then shot("sd_a.png") end
  if f==40 then quit() end
end
