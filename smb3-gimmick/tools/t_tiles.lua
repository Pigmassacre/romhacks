dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,x0,x1,y0,y1=P:match("(%S+) (%d+) (%d+) (%d+) (%d+)")
loadstate(OUT.."lv_"..name..".mss")
FRAME=function(f)
  if f==2 then
    for y=tonumber(y0),tonumber(y1),16 do
      local t={}
      for x=tonumber(x0),tonumber(x1),16 do
        local scr=x//256
        t[#t+1]=string.format("%02x",r(0x6000+scr*0x1B0+(y//16)*16+(x%256)//16))
      end
      log(string.format("y=%3d ",y)..table.concat(t," "))
    end
    quit()
  end
end
