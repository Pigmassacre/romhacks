dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local name=io.open(OUT.."param.txt"):read("l")
loadstate(OUT.."lv_"..name..".mss")
FRAME=function(f)
  if f==2 then
    for row=0,26 do
      local t={}
      for scr=0,14 do
        for col=0,15 do
          t[#t+1]=string.format("%02x",r(0x6000+scr*0x1B0+row*16+col))
        end
      end
      log(string.format("%2d ",row)..table.concat(t," "))
    end
    quit()
  end
end
