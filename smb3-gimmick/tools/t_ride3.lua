dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
local function s8(v) return (v+128)%256-128 end
local P=io.open(OUT.."param.txt"):read("l")
local svy,hold=P:match("(%-?%d+) (%S+)")
svy=tonumber(svy)
INPUT=function(f)
  local t={}
  if hold=="right" and f>=20 then t.right=true end
  if hold=="left" and f>=20 then t.left=true end
  return t
end
local maxjit,fell=0,nil
base=nil
FRAME=function(f)
  if f==10 then
    local px=rs("Player_XHi")*256+rs("Player_X")
    ws("Star_State",0,1) ws("Star_X",0,(px+2)%256) ws("Star_XHi",0,(px+2)//256)
    ws("Star_Y",0,400-256) ws("Star_YHi",0,1) ws("Star_XVel",0,0) ws("Star_YVel",0,0) ws("Star_SavedYVel",0,svy)
    ws("Star_Floor",0,1) ws("Star_PrevFloor",0,0) ws("Star_Wall",0,0) ws("Star_Standable",0,1) ws("Star_StillCnt",0,0)
    ws("Star_XFrac",0,0) ws("Star_YFrac",0,0) ws("Star_Ridden",0,1)
    ws("Player_Y",0,368-256) ws("Player_YHi",0,1) ws("Player_InAir",0,0) ws("Player_YVel",0,0)
  end
  if f>10 then
    local py=rs("Player_YHi")*256+rs("Player_Y")
    local sy=rs("Star_YHi")*256+rs("Star_Y")
    local rid=rs("Star_Ridden")
    local so=rs("Player_SprOff")
    local ptop=999
    for i=0,5 do local y=rs("Sprite_RAM",so+i*4) if y<0xF0 and y<ptop then ptop=y end end
    local sty=rs("Sprite_RAM",so+0x10)
    local stx=rs("Sprite_RAM",so+0x13)
    local d=sty-ptop
    if rs("Star_State")==1 and not fell then
      if rid==0 then fell=f end
      if base==nil then base=d end
      local j=math.abs(d-base)
      if j>maxjit then maxjit=j end
    end
    log(string.format("f=%d oam ptop=%d sty=%d d=%d stx=%d psx=%d | end py=%d sy=%d svy=%d rid=%d air=%d px=%d sx=%d",f,ptop,sty,d,stx,rs("Player_SpriteX"),py,sy,s8(rs("Star_YVel")),rid,rs("Player_InAir"),rs("Player_XHi")*256+rs("Player_X"),rs("Star_XHi")*256+rs("Star_X")))
  end
  if f==140 then log("MAXJIT "..maxjit.." FELL "..tostring(fell)) quit() end
end
