dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
local function s8(v) return (v+128)%256-128 end
INPUT=function(f)
  local t={}
  if f>=5 and f<40 then t.right=true end
  if f>=40 and f<90 then t.b=true end
  return t
end
FRAME=function(f)
  local o=""
  for i=0,4 do o=o..string.format(" [%d st=%d x=%d y=%d]",i,rs("Objects_State",i),rs("Objects_XHi",i)*256+rs("Objects_X",i),rs("Objects_YHi",i)*256+rs("Objects_Y",i)) end
  log(string.format("f=%d st=%02x sx=%d sy=%d hp=%d px=%d%s",f,rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y"),rs("Gim_Health"),rs("Player_XHi")*256+rs("Player_X"),o))
  if f==100 or f==110 or f==120 then shot(string.format("k_%03d.png",f)) end
  if f==200 then quit() end
end
