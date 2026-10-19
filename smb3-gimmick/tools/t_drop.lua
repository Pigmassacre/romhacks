dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,x,y=P:match("(%S+) (%d+) (%d+)")
x=tonumber(x) y=tonumber(y)
loadstate(OUT.."lv_"..name..".mss")
FRAME=function(f)
  ws("Gim_Health",0,3)
  if f==3 then
    ws("Player_X",0,x%256) ws("Player_XHi",0,x//256)
    ws("Player_Y",0,y%256) ws("Player_YHi",0,y//256)
    ws("Player_InAir",0,1) ws("Player_YVel",0,0) ws("Player_XVel",0,0)
  end
  if f>=3 then
    log(string.format("f=%d px=%d py=%d xv=%d yv=%d air=%d sl=%02x gl=%02x gr=%02x dying=%d",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),(rs("Player_XVel")+128)%256-128,(rs("Player_YVel")+128)%256-128,rs("Player_InAir"),rs("Level_Tile_Slope"),rs("Level_Tile_GndL"),rs("Level_Tile_GndR"),rs("Player_IsDying")))
  end
  if F_LAND==nil and f>3 and rs("Player_InAir")==0 then F_LAND=f shot("drop_land.png") end
  if F_LAND and f==F_LAND+1 then shot("drop_land1.png") end
  if f==70 then quit() end
end
