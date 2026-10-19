dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local frames,mode,px,py=P:match("(%d+) (%S+) (%d+) (%d+)")
frames,px,py=tonumber(frames),tonumber(px),tonumber(py)
loadstate(OUT.."lv_W10FL.mss")
local boss,last
INPUT=function(f)
  if f<10 then return {} end
  if not boss or rs("Objects_Var5",boss)<2 then return {right=true} end
  if mode=="star" then return {b=(f%60)<40, left=(f%120)<10} end
  return {}
end
FRAME=function(f)
  ws("Player_FlashInv",0,0x10)
  if f==3 then
    ws("Player_X",0,px%256) ws("Player_XHi",0,px>>8)
    ws("Player_Y",0,py%256) ws("Player_YHi",0,py>>8)
    local hs=px-64
    ws("Horz_Scroll",0,hs%256) ws("Horz_Scroll_Hi",0,hs>>8)
  end
  if f%100==0 and not boss then shot(string.format("bb_none_%04d.png",f)) log(string.format("f=%d px=%d py=%d",f,rs("Player_XHi")*256+rs("Player_X"),rs("Player_YHi")*256+rs("Player_Y"))) end
  if not boss then
    for i=0,4 do
      local id=rs("Level_ObjectID",i)
      if (id==0x4B or id==0x4C) and rs("Objects_State",i)~=0 then boss=i end
    end
  end
  if boss then
    if mode=="stomp" and f%120==0 then
      local bx=rs("Objects_XHi",boss)*256+rs("Objects_X",boss)
      local by=rs("Objects_YHi",boss)*256+rs("Objects_Y",boss)-56
      ws("Player_X",0,bx%256) ws("Player_XHi",0,bx>>8)
      ws("Player_Y",0,by%256) ws("Player_YHi",0,by>>8)
      ws("Player_YVel",0,0x20) ws("Player_InAir",0,1)
    end
    if mode=="stomp" and rs("Player_YVel")==0xD0 then log("f="..f.." bounce frame="..rs("Objects_Frame",boss)) end
    local s=string.format("id=%02x var5=%d t2=%d frame=%d hit=%d",rs("Level_ObjectID",boss),rs("Objects_Var5",boss),rs("Objects_Timer2",boss),rs("Objects_Frame",boss),rs("Objects_HitCount",boss))
    local key=s:gsub(" t2=%d+",""):gsub(" frame=%d+","")
    if key~=last then last=key log("f="..f.." "..s.." hp="..rs("Gim_Health")) shot(string.format("bb_%04d.png",f)) end
  end
  if f>=frames then quit() end
end
