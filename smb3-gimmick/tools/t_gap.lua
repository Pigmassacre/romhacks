dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,scroll,sx,sy,jx=P:match("(%S+) (%d+) (%d+) (%d+) (%d+)")
scroll,sx,sy,jx=tonumber(scroll),tonumber(sx),tonumber(sy),tonumber(jx)
TRACE=P:match("trace")
loadstate(OUT.."lv_"..name..".mss")
local placed,jf
local function px() return rs("Player_XHi")*256+rs("Player_X") end
INPUT=function(f)
  if not placed then return {} end
  local t={right=true}
  if not jf and px()>=jx then jf=f end
  if jf and f<jf+30 then t.a=true end
  return t
end
FRAME=function(f)
  local hs=rs("Horz_Scroll_Hi")*256+rs("Horz_Scroll")
  if not placed then
    local x=hs+40
    ws("Player_X",0,x%256) ws("Player_XHi",0,x>>8)
    ws("Player_Y",0,0x40) ws("Player_YHi",0,1)
    ws("Player_XVel",0,0) ws("Player_YVel",0,0)
    ws("Player_FlashInv",0,0x10)
    if hs>=scroll then
      placed=f
      ws("Player_X",0,sx%256) ws("Player_XHi",0,sx>>8)
      ws("Player_Y",0,sy%256) ws("Player_YHi",0,sy>>8)
      ws("Player_XVel",0,23) ws("Player_InAir",0,0)
    end
    return
  end
  if TRACE then log(string.format("f=%d x=%d y=%d vx=%d vy=%d air=%d",f-placed,px(),rs("Player_YHi")*256+rs("Player_Y"),rs("Player_XVel"),rs("Player_YVel"),rs("Player_InAir"))) end
  if f>=placed+120 or rs("Player_IsDying")~=0 or rs("Player_YHi")*256+rs("Player_Y")>400 then
    log(string.format("jx=%d jumped_at=%s x=%d y=%d air=%d dying=%d hs=%d",jx,jf and tostring(f-placed) or "-",px(),rs("Player_YHi")*256+rs("Player_Y"),rs("Player_InAir"),rs("Player_IsDying"),hs))
    quit()
  end
end
