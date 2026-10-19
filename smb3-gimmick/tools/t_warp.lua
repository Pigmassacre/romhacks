dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local name=io.open(OUT.."param.txt"):read("l")
warp(name)
INPUT=function(f)
  if f>=120 and f<125 then return {start=true} end
  if f>=200 and f<205 then return {start=true} end
  if f>=700 and f<760 and f%40<4 then return {right=true} end
  if f>=800 and f<900 and f%40<4 then return {up=true} end
  if f>=1000 and f<1100 and f%20<3 then return {a=true} end
  return {}
end
FRAME=function(f)
  if f==1200 then shot("lv_"..name..".png"); savestate(OUT.."lv_"..name..".mss") end
  if f==1202 then quit() end
end
