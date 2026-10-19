dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
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
  ws("Gim_Health",0,3)
  log(string.format("f=%d px=%d py=%d xv=%d yv=%d air=%d slope=%02x slide=%d inv=%d pad=%02x onsl=%d",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),(rs("Player_XVel")+128)%256-128,(rs("Player_YVel")+128)%256-128,rs("Player_InAir"),rs("Level_Tile_Slope"),rs("Player_Slide"),rs("Player_FlashInv"),rs("Pad_Holding"),rs("Gim_OnSlope")))
  if f%shotEvery==0 then shot(string.format("sl_%s_%04d.png",name,f)) end
  if f>total+60 then quit() end
end
