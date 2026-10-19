dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
function ws(name,v) emu.write(S[name],v%256,M) end
loadstate(OUT.."w11.mss")
local function s8(v) return (v+128)%256-128 end
INPUT=function(f)
  local t={}
  if f>=5 and f<30 then t.a=true end
  if f>=120 and f<140 then t.right=true end
  if f>=150 and f<160 then t.a=true end
  return t
end
FRAME=function(f)
  if f==8 then
    ws("Star_State",1) ws("Star_X",rs("Player_X")+2) ws("Star_XHi",rs("Player_XHi"))
    ws("Star_Y",400-256) ws("Star_YHi",1) ws("Star_XVel",0) ws("Star_YVel",-60) ws("Star_SavedYVel",-60)
    ws("Star_Floor",0) ws("Star_Wall",0) ws("Star_Standable",1) ws("Star_StillCnt",0) ws("Star_XFrac",0) ws("Star_YFrac",0)
  end
  log(string.format("f=%d st=%02x sx=%d sy=%d svx=%d svy=%d fl=%d rid=%d still=%d | px=%d py=%d pvx=%d pvy=%d air=%d gf=%d",
    f,rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y"),s8(rs("Star_XVel")),s8(rs("Star_YVel")),
    rs("Star_Floor"),rs("Star_Ridden"),rs("Star_StillCnt"),
    rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),s8(rs("Player_XVel")),s8(rs("Player_YVel")),rs("Player_InAir"),rs("Gim_Frame")))
  if f==60 or f==75 then shot(string.format("r_%03d.png",f)) end
  if f==200 then quit() end
end
