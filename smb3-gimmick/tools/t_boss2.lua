dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,frames,mode=P:match("(%S+) (%d+) (%S+)")
frames=tonumber(frames)
loadstate(OUT.."lv_"..name..".mss")
local boss
INPUT=function(f)
  if f<2 then return {} end
  if mode=="star" then return {b=(f%60)<40, right=(f%120)<20} end
  return {right=true,a=(f%70)<25}
end
FRAME=function(f)
  ws("Player_FlashInv",0,0x10)
  if not boss then
    for i=0,7 do if rs("Level_ObjectID",i)==0x0E and rs("Objects_State",i)~=0 then boss=i end end
  end
  if mode=="stomp" and boss and f%90==0 then
    local bx=rs("Objects_XHi",boss)*256+rs("Objects_X",boss)
    local by=rs("Objects_YHi",boss)*256+rs("Objects_Y",boss)-56
    ws("Player_X",0,bx%256) ws("Player_XHi",0,bx>>8)
    ws("Player_Y",0,by%256) ws("Player_YHi",0,by>>8)
    ws("Player_YVel",0,0x20) ws("Player_InAir",0,1)
  end
  if mode=="stomp" and boss and f%5==0 then
    log(string.format("f=%d var4=%d t2=%d py=%d vy=%d hp=%d dying=%d",f,rs("Objects_Var4",boss),rs("Objects_Timer2",boss),rs("Player_YHi")*256+rs("Player_Y"),rs("Player_YVel"),rs("Gim_Health"),rs("Player_IsDying")))
  end
  if mode~="stomp" and f%10==0 then
    local s=string.format("f=%d px=%d py=%d star=%02x sx=%d sy=%d",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y"))
    if boss then
      s=s..string.format(" boss slot=%d st=%d x=%d y=%d hit=%d v5=%d hv=%d vv=%d spx=%d spy=%d",boss,rs("Objects_State",boss),rs("Objects_XHi",boss)*256+rs("Objects_X",boss),rs("Objects_YHi",boss)*256+rs("Objects_Y",boss),rs("Objects_HitCount",boss),rs("Objects_Var5",boss),rs("Objects_SprHVis",boss),rs("Objects_SprVVis",boss),rs("Objects_SpriteX",boss),rs("Objects_SpriteY",boss))
    end
    log(s)
  end
  if f%60==0 then shot(string.format("boss_%04d.png",f)) end
  if f>=frames then quit() end
end
