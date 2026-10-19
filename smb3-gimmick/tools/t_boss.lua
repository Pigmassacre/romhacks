dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,id,mode,dur=P:match("(%S+) (%x+) (%S+) (%d+)")
id=tonumber(id,16) dur=tonumber(dur)
loadstate(OUT.."lv_"..name..".mss")
local SLOT=4
INPUT=function(f)
  if f<20 then return {} end
  if mode=="star" then
    local c=(f-20)%80
    if c<50 then return {b=true} end
    return {}
  end
  local c=(f-20)%60
  if c<16 then return {a=true,right=(f%120<60),left=(f%120>=60)} end
  return {right=(f%120<60),left=(f%120>=60)}
end
FRAME=function(f)
  if f==5 then
    local x=rs("Player_XHi")*256+rs("Player_X")+96
    ws("Level_ObjectID",SLOT,id)
    ws("Objects_State",SLOT,1)
    ws("Objects_X",SLOT,x%256) ws("Objects_XHi",SLOT,x>>8)
    ws("Objects_Y",SLOT,0x60) ws("Objects_YHi",SLOT,1)
  end
  if f>=5 then ws("Gim_Health",0,3) end
  if f%10==0 then log(string.format("f=%d px=%d py=%d yv=%d air=%d hp=%d | id=%02x st=%d hc=%d v5=%d frame=%d ox=%d oy=%d | star=%d ride=%d",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),(rs("Player_YVel")+128)%256-128,rs("Player_InAir"),rs("Gim_Health"),rs("Level_ObjectID",SLOT),rs("Objects_State",SLOT),rs("Objects_HitCount",SLOT),rs("Objects_Var5",SLOT),rs("Objects_Frame",SLOT),rs("Objects_XHi",SLOT)*256+rs("Objects_X",SLOT),rs("Objects_YHi",SLOT)*256+rs("Objects_Y",SLOT),rs("Star_State"),rs("Star_Ridden"))) end
  if f%100==0 then shot(string.format("boss_%s_%04d.png",mode,f)) end
  if f>=dur then quit() end
end
