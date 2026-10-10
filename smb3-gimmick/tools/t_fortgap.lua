dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local ext,jx=P:match("(%d+) (%d+)")
ext,jx=tonumber(ext),tonumber(jx)
loadstate(OUT.."lv_W10FL.mss")
local jf
INPUT=function(f)
  if f<10 then return {} end
  local t={right=true}
  if not jf and rs("Player_XHi")*256+rs("Player_X")>=jx then jf=f end
  if jf and f<jf+40 then t.a=true end
  return t
end
FRAME=function(f)
  if f==3 then
    for i=0,ext-1 do emu.write(0x6000+2*0x1B0+24*16+6+i,0xE4,M) end
    ws("Player_XHi",0,2) ws("Player_X",0,16+8)
    ws("Player_YHi",0,1) ws("Player_Y",0,(22*16)%256)
    ws("Horz_Scroll_Hi",0,1) ws("Horz_Scroll",0,0xC0)
  end
  if f==300 or rs("Player_IsDying")~=0 then
    log(string.format("ext=%d jx=%d x=%d y=%d dying=%d air=%d",ext,jx,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),rs("Player_IsDying"),rs("Player_InAir")))
    shot(string.format("fg_%d_%d.png",ext,jx))
    quit()
  end
end
