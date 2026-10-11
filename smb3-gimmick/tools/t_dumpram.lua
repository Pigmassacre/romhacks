dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local name=io.open(OUT.."param.txt"):read("l")
loadstate(OUT.."lv_"..name..".mss")
FRAME=function(f)
  if f==2 then
    local t={}
    for i=0,7 do t[#t+1]=string.char(rs("Tile_AttrTable",i)) end
    t[#t+1]=string.char(rs("Level_7Vertical"))
    for a=0x6000,0x7FFF do t[#t+1]=string.char(r(a)) end
    local h=io.open(OUT.."ram_"..name..".bin","wb") h:write(table.concat(t)) h:close()
    quit()
  end
end
