dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local name=io.open(OUT.."param.txt"):read("l")
warp(name)
INPUT=function(f)
  if f>=120 and f<125 then return {start=true} end
  if f>=200 and f<205 then return {start=true} end
  if f>=700 and f<760 and f%40<4 then return {right=true} end
  if f>=800 and f<900 and f%40<4 then return {up=true} end
  if f>=1000 and f<1100 and f%20<3 then return {a=true} end
  if f>=1200 then return {right=true} end
  return {}
end
FRAME=function(f)
  if f>=1200 then
    local sc=rs("Splash_Counter")..","..rs("Splash_Counter",1)..","..rs("Splash_Counter",2)
    log(string.format("f=%d px=%d py=%d water=%d splash=%s",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_Y"),rs("Player_InWater"),sc))
    if rs("Splash_Counter")+rs("Splash_Counter",1)+rs("Splash_Counter",2)>0 and f%3==0 then shot(string.format("sp_%04d.png",f)) end
    if rs("Player_InWater")~=0 and f%30==0 then shot(string.format("sw_%04d.png",f)) end
  end
  if f>=1600 then quit() end
end
