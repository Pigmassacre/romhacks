dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local name=io.open(OUT.."param.txt"):read("l")
loadstate(OUT.."lv_"..name..".mss")
FRAME=function(f)
  if f==2 then
    local a={}
    for i=0,7 do a[i]=rs("Tile_AttrTable",i) end
    for row=0,26 do
      local t={}
      for scr=0,14 do
        for col=0,15 do
          local v=r(0x6000+scr*0x1B0+row*16+col)
          local q=v>>6
          local c="."
          if v>=a[q+4] then c="#" elseif v>=a[q] then c="=" end
          t[#t+1]=c
        end
      end
      log(string.format("%2d ",row)..table.concat(t))
    end
    quit()
  end
end
