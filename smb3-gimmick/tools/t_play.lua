dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
INPUT=function(f)
  local t={right=true}
  local p=f%90
  if p<18 then t.a=true end
  local q=f%200
  if q>=100 and q<150 then t.b=true end
  return t
end
FRAME=function(f)
  if f%10==0 then
    log(string.format("f=%d px=%d py=%d hp=%d st=%02x dying=%d air=%d gf=%d mode=%d",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),
      rs("Gim_Health"),rs("Star_State"),rs("Player_IsDying"),rs("Player_InAir"),rs("Gim_Frame"),rs("Level_ExitToMap")))
  end
  if f%150==0 then shot(string.format("p_%04d.png",f)) end
  if f==1800 then quit() end
end
