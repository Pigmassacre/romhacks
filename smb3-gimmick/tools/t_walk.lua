dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
INPUT=function(f)
  if f<5 then return {} end
  if f<60 then return {right=true} end
  if f<64 then return {right=true,a=true} end
  if f<90 then return {right=true,a=true} end
  if f<140 then return {} end
  if f<170 then return {left=true} end
  return {}
end
FRAME=function(f)
  log(string.format("hp=%d ride=%d o=%d,%d,%d f=%d x=%d y=%d xv=%d yv=%d air=%d gf=%d cnt=%d flip=%02x bank=%02x",rs("Gim_Health"),rs("Gim_RideSlot"),rs("Objects_State"),rs("Objects_State",1),rs("Objects_State",2),f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),
    (rs("Player_XVel")+128)%256-128,(rs("Player_YVel")+128)%256-128,rs("Player_InAir"),rs("Gim_Frame"),rs("Gim_AnimCnt"),rs("Player_FlipBits"),rs("PatTable_BankSel",2)))
  if f==180 or f==186 or f==192 or f==198 or f==215 or f==218 then shot(string.format("w_%03d.png",f)) end
  if f==220 then quit() end
end
