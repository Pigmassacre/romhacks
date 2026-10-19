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
local function tile(x,y)
  local scr=x//256
  return r(0x6000+scr*0x1B0+(y//16)*16+(x%256)//16)
end
FRAME=function(f)
  ws("Gim_Health",0,3)
  if f==1 then
    local t={} for i=0,7 do t[#t+1]=string.format("%02x",rs("Tile_AttrTable",i)) end
    log("attr "..table.concat(t," "))
  end
  local sx=rs("Star_XHi")*256+rs("Star_X")
  local sy=rs("Star_YHi")*256+rs("Star_Y")
  log(string.format("f=%d px=%d py=%d st=%d sx=%d sy=%d svx=%d svy=%d fl=%d os=%d tc=%02x tb=%02x",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),rs("Star_State"),sx,sy,(rs("Star_XVel")+128)%256-128,(rs("Star_YVel")+128)%256-128,rs("Star_Floor"),rs("Star_OnSlope"),tile(sx+8,sy+8),tile(sx+8,sy+16)))
  if f%shotEvery==0 then shot(string.format("ss_%s_%04d.png",name,f)) end
  if f>total+60 then quit() end
end
