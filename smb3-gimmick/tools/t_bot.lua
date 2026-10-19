dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,dur,dir=P:match("(%S+) (%d+) (%S+)")
dur=tonumber(dur)
warp(name)
local start=nil
INPUT=function(f)
  if not start then
    if f>=120 and f<125 then return {start=true} end
    if f>=200 and f<205 then return {start=true} end
    if f>=700 and f<760 and f%40<4 then return {right=true} end
    if f>=800 and f<900 and f%40<4 then return {up=true} end
    if f>=1000 and f<1100 and f%20<3 then return {a=true} end
    return {}
  end
  local g=f-start
  local t={}
  t[dir]=true
  if dir=="up" then t.right=(g%240<120) t.left=not t.right end
  if g%45<20 then t.a=true end
  if g%150>=60 and g%150<110 then t.b=true end
  return t
end
FRAME=function(f)
  if not start then
    if f==1200 then start=f end
    return
  end
  local g=f-start
  ws("Player_StarInv",0,0x40)
  if rs("Level_7Vertical")==0 and rs("Player_YHi")==1 and rs("Player_Y")>=0x90 and rs("Player_IsDying")==0 then ws("Player_YVel",0,-0x7F) end
  if g%15==0 then log(string.format("g=%d px=%d py=%d air=%d vert=%d water=%d climb=%d pipe=%d dying=%d gf=%d anim=%d st=%02x end=%d",g,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),rs("Player_InAir"),rs("Level_7Vertical"),rs("Player_InWater"),rs("Player_IsClimbing"),rs("Level_PipeMove"),rs("Player_IsDying"),rs("Gim_Frame"),rs("Gim_Animated"),rs("Star_State"),rs("Player_EndLevel"))) end
  if g%200==0 then shot(string.format("bot_%s_%04d.png",name,g)) end
  if g==dur then quit() end
end
