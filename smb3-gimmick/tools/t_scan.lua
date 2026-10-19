dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local name=io.open(OUT.."param.txt"):read("l")
loadstate(OUT.."lv_"..name..".mss")
FRAME=function(f)
  if f==3 then
    for a=0,0x1B0*15-1 do
      local t=r(0x6000+a)
      if t==0xAD or t==0xB5 or t==0xAF or t==0xB3 then
        local scr=a//0x1B0
        local rem=a%0x1B0
        log(string.format("%s tile=%02x x=%d y=%d",name,t,scr*256+(rem%16)*16,(rem//16)*16))
      end
    end
    quit()
  end
end
