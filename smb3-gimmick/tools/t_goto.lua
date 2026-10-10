dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,tx,ty,press,dur=P:match("(%S+) (%d+) (%d+) (%S+) (%d+)")
tx=tonumber(tx) ty=tonumber(ty) dur=tonumber(dur)
loadstate(OUT.."lv_"..name..".mss")
local arrived=nil
local function px() return rs("Player_XHi")*256+rs("Player_X") end
INPUT=function(f)
  if not arrived then
    return {}
  end
  local t={}
  for k in press:gmatch("[^,]+") do t[k]=true end
  return t
end
FRAME=function(f)
  if not arrived then
    ws("Player_StarInv",0,0x40)
  elseif f==arrived+1 then
    ws("Player_StarInv",0,0)
  end
  if not arrived then
    if f>=30 then
      local x=px()+3
      ws("Player_X",0,x%256) ws("Player_XHi",0,x>>8)
      local y=ty-40
      ws("Player_Y",0,y%256) ws("Player_YHi",0,y>>8)
      ws("Player_YVel",0,0) ws("Player_XVel",0,0)
    end
    if px()>=tx then
      arrived=f
      ws("Player_X",0,(tx+8)%256) ws("Player_XHi",0,(tx+8)>>8)
      local y=ty-40
      ws("Player_Y",0,y%256) ws("Player_YHi",0,y>>8)
      ws("Player_XVel",0,0) ws("Player_YVel",0,0)
    end
  end
  if f%3==0 then log(string.format("f=%d px=%d py=%d air=%d vert=%d water=%d climb=%d pipe=%02x dying=%d gf=%d anim=%d pf=%02x gl=%02x gr=%02x",f,px(),rs("Player_YHi")*256+rs("Player_Y"),rs("Player_InAir"),rs("Level_7Vertical"),rs("Player_InWater"),rs("Player_IsClimbing"),rs("Level_PipeMove"),rs("Player_IsDying"),rs("Gim_Frame"),rs("Gim_Animated"),rs("Player_Frame"),rs("Level_Tile_GndL"),rs("Level_Tile_GndR"))) end
  if arrived and (f-arrived)%20==0 then shot(string.format("g_%s_%04d.png",name,f-arrived)) end
  if arrived and f-arrived>=dur then
    local s="ppu"
    for i=0,31 do s=s..string.format(" %02x",emu.read(i,emu.memType.nesPaletteRam)) end
    s=s.."\npal"
    for i=0,31 do s=s..string.format(" %02x",rs("Pal_Data",i)) end
    log(s..string.format("\ntileset=%d",rs("Level_Tileset")))
    quit()
  end
  if f>6000 then log("never arrived") quit() end
end
