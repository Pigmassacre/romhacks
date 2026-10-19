dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local seq={}
INPUT=function(f)
  if f>=120 and f<125 then return {start=true} end
  if f>=200 and f<205 then return {start=true} end
  if f>=700 and f<760 and f%40<4 then return {right=true} end
  if f>=800 and f<900 and f%40<4 then return {up=true} end
  if f>=1000 and f<1100 and f%20<3 then return {a=true} end
  return {}
end
FRAME=function(f)
  if f%20==0 then log(string.format("f=%d mapx=%d mapy=%d op=%d ts=%d",f,rs("World_Map_X"),rs("World_Map_Y"),rs("Map_Operation"),rs("Level_Tileset"))) end
  if f==1130 then shot("t11.png"); savestate(OUT.."w11.mss") end
  if f==1132 then quit() end
end
