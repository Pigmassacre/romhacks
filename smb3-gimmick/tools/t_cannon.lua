dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."lv_W1AIR.mss")
local mode=io.open(OUT.."param.txt"):read("l")
local function s8(v) return (v+128)%256-128 end
local SLOT=7
INPUT=function(f)
  local t={}
  if mode=="star" and f>=12 and f<60 then t.b=true end
  if mode=="ride" and f>=100 and f<103 then t.a=true end
  return t
end
FRAME=function(f)
  if f==10 then
    local px=rs("Player_XHi")*256+rs("Player_X")
    local py=rs("Player_YHi")*256+rs("Player_Y")
    local bx,by,vx=px+40,py,-16
    if mode=="ride" then bx,by,vx=px+4,py-10,-8 ws("Player_Y",0,(py-60)%256) ws("Player_YHi",0,(py-60)//256) ws("Player_YVel",0,0) ws("Player_InAir",0,1) end
    if mode=="star" then bx,by,vx=px+120,py+16,-8 end
    if mode=="side" then by=py+16 end
    ws("SpecialObj_ID",SLOT,0x0B) ws("SpecialObj_XLo",SLOT,bx%256) ws("SpecialObj_YLo",SLOT,by%256) ws("SpecialObj_YHi",SLOT,by//256)
    ws("SpecialObj_XVel",SLOT,vx) ws("SpecialObj_YVel",SLOT,0) ws("SpecialObj_Data",SLOT,0)
    ws("SpecialObj_XVelFrac",SLOT,0) ws("SpecialObj_YVelFrac",SLOT,0)
  end
  if f>10 then
    log(string.format("f=%d px=%d py=%d pyv=%d air=%d ride=%02x hp=%d | id=%02x bx=%d by=%d data=%d | star=%02x sx=%d sy=%d",
      f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),s8(rs("Player_YVel")),rs("Player_InAir"),rs("Gim_RideSlot"),rs("Gim_Health"),
      rs("SpecialObj_ID",SLOT),rs("SpecialObj_XLo",SLOT),rs("SpecialObj_YHi",SLOT)*256+rs("SpecialObj_YLo",SLOT),rs("SpecialObj_Data",SLOT),
      rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y")))
  end
  if f==20 or f==60 or f==90 or f==110 then shot("cannon_"..mode.."_"..f..".png") end
  if f==150 then quit() end
end
