dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local state,sx,sy,svx,svy=P:match("(%S+) (%d+) (%d+) (%S+) (%S+)")
sx=tonumber(sx) sy=tonumber(sy) svx=tonumber(svx) svy=tonumber(svy)
loadstate(OUT..state)
local function s8(v) return (v+128)%256-128 end
FRAME=function(f)
  if f==10 then
    ws("Star_State",0,1) ws("Star_X",0,sx%256) ws("Star_XHi",0,sx>>8) ws("Star_Y",0,sy%256) ws("Star_YHi",0,sy>>8)
    ws("Star_XVel",0,svx) ws("Star_YVel",0,svy) ws("Star_SavedXVel",0,svx) ws("Star_SavedYVel",0,svy)
    ws("Star_Standable",0,1) ws("Star_StillCnt",0,0) ws("Star_Floor",0,0) ws("Star_Wall",0,0) ws("Star_Ridden",0,0)
    local px,py=sx,sy-32
    ws("Player_X",0,px%256) ws("Player_XHi",0,px>>8) ws("Player_Y",0,py%256) ws("Player_YHi",0,py>>8)
    ws("Player_XVel",0,0) ws("Player_YVel",0,0) ws("Player_InAir",0,1)
  end
  if f>=10 then
    log(string.format("f=%d st=%02x sx=%d sy=%d svx=%d svy=%d rid=%d | px=%d py=%d pvy=%d air=%d",
      f,rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y"),s8(rs("Star_XVel")),s8(rs("Star_YVel")),rs("Star_Ridden"),
      rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),s8(rs("Player_YVel")),rs("Player_InAir")))
    if f%4==0 then shot(string.format("rc_%04d.png",f)) end
  end
  if f==70 then quit() end
end
