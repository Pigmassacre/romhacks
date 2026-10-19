dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local words={}
for w in P:gmatch("%S+") do words[#words+1]=w end
local name=table.remove(words,1)
local shotEvery=tonumber(table.remove(words,1))
local steps={}
local total=0
for _,w in ipairs(words) do
  local n,b=w:match("(%d+):(%S*)")
  local t={}
  for k in b:gmatch("[^,]+") do t[k]=true end
  total=total+tonumber(n)
  steps[#steps+1]={total,t}
end
loadstate(OUT.."lv_"..name..".mss")
INPUT=function(f)
  for _,s in ipairs(steps) do if f<=s[1] then return s[2] end end
  return {}
end
FRAME=function(f)
  if (f%5==0 or (f>=160 and f<=185)) then log(string.format("f=%d px=%d py=%d xv=%d yv=%d air=%d vert=%d water=%d climb=%d pipe=%d dying=%d gf=%d anim=%d pf=%02x st=%02x hp=%d mode=%d gl=%02x gr=%02x",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),(rs("Player_XVel")+128)%256-128,(rs("Player_YVel")+128)%256-128,rs("Player_InAir"),rs("Level_7Vertical"),rs("Player_InWater"),rs("Player_IsClimbing"),rs("Level_PipeMove"),rs("Player_IsDying"),rs("Gim_Frame"),rs("Gim_Animated"),rs("Player_Frame"),rs("Star_State"),rs("Gim_Health"),rs("Player_HitCeiling"),rs("Level_Tile_GndL"),rs("Level_Tile_GndR"))) end
  if f%shotEvery==0 then shot(string.format("s_%s_%04d.png",name,f)) end
  if f>total+60 then quit() end
end
local wa=S["Player_YHi"]
emu.addMemoryCallback(function(addr,val)
  if val>2 and val<0xF0 then
    local st=emu.getState()
    local ca=emu.convertAddress(st["cpu.pc"],M)
    log(string.format("WRITE YHi=%02x pc=%04x a=%02x x=%02x y=%02x f=%d rom=%x bank=%d",val,st["cpu.pc"],st["cpu.a"],st["cpu.x"],st["cpu.y"],F,ca.address,ca.address//0x2000))
  end
end, emu.callbackType.write, wa, wa)
