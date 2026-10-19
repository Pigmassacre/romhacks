dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,cx,cy,vx,vy=P:match("(%S+) (%d+) (%d+) (%-?%d+) (%-?%d+)")
cx,cy,vx,vy=tonumber(cx),tonumber(cy),tonumber(vx),tonumber(vy)
loadstate(OUT.."lv_"..name..".mss")
local S0=7
FRAME=function(f)
  ws("Player_FlashInv",0,0x10)
  if f==5 then
    ws("SpecialObj_ID",S0,0x0B)
    ws("SpecialObj_XLo",S0,cx) ws("SpecialObj_YLo",S0,cy) ws("SpecialObj_YHi",S0,0)
    ws("SpecialObj_XVel",S0,vx) ws("SpecialObj_YVel",S0,vy) ws("SpecialObj_Data",S0,0)
    ws("Player_X",0,cx) ws("Player_XHi",0,0)
    ws("Player_Y",0,cy-31) ws("Player_YHi",0,0)
    ws("Player_YVel",0,0) ws("Player_XVel",0,0)
  end
  if f>5 and f%3==0 then
    log(string.format("f=%d px=%d py=%d air=%d ride=%02x cx=%d cy=%d",f,rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),rs("Player_InAir"),rs("Gim_RideSlot"),rs("SpecialObj_XLo",S0),rs("SpecialObj_YLo",S0)))
  end
  if f==30 or f==60 then shot(string.format("cride_%d.png",f)) end
  if f>=70 then quit() end
end
