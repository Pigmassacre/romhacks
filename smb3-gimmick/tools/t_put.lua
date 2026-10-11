-- param: <level> <shot every> <x> <y> <frames>:<buttons> ...   Places Yumetaro at x,y (0 0: leave him), then plays the inputs
dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local words={}
for w in P:gmatch("%S+") do words[#words+1]=w end
local name=table.remove(words,1)
local shotEvery=tonumber(table.remove(words,1))
local x0=tonumber(table.remove(words,1))
local y0=tonumber(table.remove(words,1))
local steps={}
local total=5
for _,w in ipairs(words) do
  local n,b=w:match("(%d+):(%S*)")
  local t={}
  for k in b:gmatch("[^,]+") do t[k]=true end
  total=total+tonumber(n)
  steps[#steps+1]={total,t}
end
loadstate(OUT.."lv_"..name..".mss")
local placed
INPUT=function(f)
  if not placed then return {} end
  for _,s in ipairs(steps) do if f-placed<=s[1] then return s[2] end end
  return {}
end
local function sg(n) return (rs(n)+128)%256-128 end
local function put(x,y)
  ws("Player_X",0,x%256) ws("Player_XHi",0,x>>8)
  ws("Player_Y",0,y%256) ws("Player_YHi",0,y>>8)
  ws("Player_XVel",0,0) ws("Player_YVel",0,0)
end
FRAME=function(f)
  if not placed then
    -- Drag him along in the sky until the screen has scrolled to the spot
    local hs=rs("Horz_Scroll_Hi")*256+rs("Horz_Scroll")
    if x0==0 then placed=f return end
    if f<3 then return end
    if rs("Level_7Vertical")~=0 or hs>=x0-128 or f>9000 then placed=f put(x0,y0) return end
    put(hs+132,0x140) ws("Player_FlashInv",0,0x10)
    return
  end
  f=f-placed+5
  ws("Player_FlashInv",0,0x10)
  log(string.format("f=%d px=%d py=%d xv=%d yv=%d air=%d pipe=%d dying=%d st=%02x sx=%d sy=%d rid=%d hp=%d vs=%d hs=%d",f-5,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"),sg("Player_XVel"),sg("Player_YVel"),rs("Player_InAir"),rs("Level_PipeMove"),rs("Player_IsDying"),rs("Star_State"),rs("Star_XHi")*256+rs("Star_X"),rs("Star_YHi")*256+rs("Star_Y"),rs("Star_Ridden"),rs("Gim_Health"),rs("Level_VertScrollH")*256+rs("Level_VertScroll"),rs("Horz_Scroll_Hi")*256+rs("Horz_Scroll")))
  if f%shotEvery==0 then shot(string.format("s_%s_%04d.png",name,f)) end
  if f>total+30 then quit() end
end
