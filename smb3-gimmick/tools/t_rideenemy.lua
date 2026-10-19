dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,id,nth,minx=P:match("(%S+) (%x+) (%d+) (%d+)")
id=tonumber(id,16) nth=tonumber(nth) minx=tonumber(minx)
loadstate(OUT.."lv_"..name..".mss")
local on=nil
local rode=0
local slot=nil
local seen={}
local count=0
local cnt={}
for _,n in ipairs({"Object_HitTestRespond","PRG000_D29B","Gim_StandOnEnemy","Player_HitEnemy","PRG000_D1C5","Player_Draw","Gim_Star","ObjNorm_GroundTroop","Object_HitTest"}) do
  cnt[n]=0
  emu.addMemoryCallback(function() cnt[n]=cnt[n]+1 end, emu.callbackType.exec, S[n], S[n])
end
INPUT=function(f)
  if not on then return {right=true, a=(f%40)<20} end
  return {}
end
FRAME=function(f)
  ws("Gim_Health",0,3)
  ws("Player_FlashInv",0,0)
  if not on then
    for i=0,4 do
      local ox=rs("Objects_XHi",i)*256+rs("Objects_X",i)
      local vis=rs("Objects_SprHVis",i)==0 and rs("Objects_SprVVis",i)==0
      if rs("Level_ObjectID",i)==id and rs("Objects_State",i)==2 and vis and not seen[i] and ox>=minx then
        seen[i]=true
        count=count+1
        if count==nth then
          local oy=rs("Objects_YHi",i)*256+rs("Objects_Y",i)
          local py=oy-31-2
          ws("Player_X",0,ox%256) ws("Player_XHi",0,ox//256)
          ws("Player_Y",0,py%256) ws("Player_YHi",0,py//256)
          ws("Player_InAir",0,1) ws("Player_YVel",0,0) ws("Player_XVel",0,0)
          on=f slot=i
          log(string.format("placed f=%d slot=%d ox=%d oy=%d",f,i,ox,oy))
          break
        end
      end
    end
    for i=0,4 do if rs("Objects_State",i)==0 then seen[i]=nil end end
  end
  if on then
    local i=slot
    local ox=rs("Objects_XHi",i)*256+rs("Objects_X",i)
    local oy=rs("Objects_YHi",i)*256+rs("Objects_Y",i)
    local px=rs("Player_XHi")*256+rs("Player_X")
    local py=rs("Player_YHi")*256+rs("Player_Y")
    local rid=rs("Gim_RideSlot")
    if f>on+2 and rid==slot+1 then rode=rode+1 end
    local so=rs("Player_SprOff")
    local ptop=999
    for k=0,5 do local yy=rs("Sprite_RAM",so+k*4) if yy<0xF0 and yy<ptop then ptop=yy end end
    log(string.format("f=%d ox=%d oy=%d px=%d py=%d dy=%d air=%d rid=%d st=%d | oamdy=%d hit=%d stomp=%d stand=%d phe=%d coll=%d pd=%d gs=%d gt=%d ht=%d",f,ox,oy,px,py,oy-py,rs("Player_InAir"),rid,rs("Objects_State",i),rs("Objects_SpriteY",i)-ptop,cnt.Object_HitTestRespond,cnt.PRG000_D29B,cnt.Gim_StandOnEnemy,cnt.Player_HitEnemy,cnt.PRG000_D1C5,cnt.Player_Draw,cnt.Gim_Star,cnt.ObjNorm_GroundTroop,cnt.Object_HitTest))
    if f==on+200 then log("RODE "..rode) quit() end
  end
  if f>3000 then log("never placed") quit() end
end
