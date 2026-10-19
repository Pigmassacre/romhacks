dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,from,to=P:match("(%S+) (%d+) (%d+)")
from=tonumber(from) to=tonumber(to)
loadstate(OUT.."lv_"..name..".mss")
FRAME=function(f)
  local sx=rs("Horz_Scroll_Hi")*256+rs("Horz_Scroll")
  local px=sx+40
  ws("Player_X",0,px%256) ws("Player_XHi",0,px>>8)
  ws("Player_Y",0,0x40) ws("Player_YHi",0,1)
  ws("Player_XVel",0,0) ws("Player_YVel",0,0)
  ws("Player_FlashInv",0,0x10)
  if sx>=from and f%16==0 then shot(string.format("view_%04d.png",sx)) end
  if sx>=to or f>20000 then log("sx="..sx.." f="..f) quit() end
end
