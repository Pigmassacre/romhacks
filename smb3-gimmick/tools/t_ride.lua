dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
local function s8(v) return (v+128)%256-128 end
local P=tonumber(io.open(OUT.."param.txt"):read("*l"))
INPUT=function(f)
  local t={}
  if f>=5 and f<55 then t.b=true end
  if f>=55+P and f<75+P then t.a=true end
  if f>=55 and f<200 then t.right=true end
  return t
end
local rode=0
FRAME=function(f)
  if rs("Star_Ridden")==1 then rode=rode+1 end
  log(string.format("f=%d st=%02x sx=%d sy=%d svx=%d svy=%d fl=%d std=%d rid=%d | px=%d py=%d pvx=%d pvy=%d air=%d",
    f,rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y"),s8(rs("Star_XVel")),s8(rs("Star_YVel")),
    rs("Star_Floor"),rs("Star_Standable"),rs("Star_Ridden"),
    rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),s8(rs("Player_XVel")),s8(rs("Player_YVel")),rs("Player_InAir")))
  if rode==3 then shot("ride.png") end
  if f==200 then log("RODE "..rode) quit() end
end
