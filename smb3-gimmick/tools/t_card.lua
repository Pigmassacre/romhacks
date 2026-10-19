dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
local hit=nil
INPUT=function(f)
  local t={right=true}
  if f%45<20 then t.a=true end
  return t
end
FRAME=function(f)
  ws("Player_StarInv",0,0x40)
  if rs("Player_YHi")==1 and rs("Player_Y")>=0x90 and rs("Player_IsDying")==0 then ws("Player_YVel",0,-0x7F) end
  local o=""
  for i=0,7 do
    if rs("Level_ObjectID",i)==0x41 and rs("Objects_State",i)~=0 then
      o=string.format(" card[%d] y=%d det=%d",i,rs("Objects_YHi",i)*256+rs("Objects_Y",i),rs("Objects_DetStat",i))
      if rs("Objects_DetStat",i)~=0 and not hit then hit=f; shot("c_hit.png") end
    end
  end
  if f%15==0 and rs("Player_XHi")>=9 then
    local s=""
    for i=0,7 do s=s..string.format(" %02x/%d@%d,%d",rs("Level_ObjectID",i),rs("Objects_State",i),rs("Objects_XHi",i)*256+rs("Objects_X",i),rs("Objects_YHi",i)*256+rs("Objects_Y",i)) end
    log("  objs"..s)
  end
  if f%15==0 then log(string.format("f=%d px=%d py=%d air=%d hp=%d end=%d dying=%d%s",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),rs("Player_InAir"),rs("Gim_Health"),rs("Player_EndLevel"),rs("Player_IsDying"),o)) end
  if f%300==0 then shot(string.format("c_%04d.png",f)) end
  if f==2400 or (hit and f==hit+200) then shot("c_end.png") quit() end
end
