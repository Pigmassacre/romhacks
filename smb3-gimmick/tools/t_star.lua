dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
local function s8(v) return (v+128)%256-128 end
INPUT=function(f)
  if f>=5 and f<55 then return {b=true} end
  if f>=70 and f<90 then return {right=true} end
  return {}
end
FRAME=function(f)
  log(string.format("f=%d st=%02x sx=%d sy=%d svx=%d svy=%d fl=%d wall=%d std=%d rid=%d still=%d | px=%d py=%d pvy=%d air=%d | obj0 st=%d x=%d",
    f,rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y"),s8(rs("Star_XVel")),s8(rs("Star_YVel")),
    rs("Star_Floor"),rs("Star_Wall"),rs("Star_Standable"),rs("Star_Ridden"),rs("Star_StillCnt"),
    rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),s8(rs("Player_YVel")),rs("Player_InAir"),
    rs("Objects_State"),rs("Objects_XHi")*256+rs("Objects_X")))
  if f==20 or f==40 or f==52 or f==60 or f==70 or f==85 or f==110 then shot(string.format("s_%03d.png",f)) end
  if f==240 then quit() end
end
