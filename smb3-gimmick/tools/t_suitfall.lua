-- Drops Yumetaro from high up wearing a map-inventory suit (param: level suit flytime frames [flap]); he must keep falling.
-- With flap, A is tapped for that many frames first (flying with a P-Wing), and he must come down after letting go
dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
local P=io.open(OUT.."param.txt"):read("l")
local name,suit,fly,dur,flap=P:match("(%S+) (%d+) (%d+) (%d+) ?(%d*)")
suit=tonumber(suit) fly=tonumber(fly) dur=tonumber(dur) flap=tonumber(flap) or 0
loadstate(OUT.."lv_"..name..".mss")
local rises,prev=0,nil
INPUT=function(f) return {a=(f>10 and f<=10+flap and f%8<4)} end
FRAME=function(f)
  if f<=10 then
    ws("Player_Suit",0,suit) ws("Player_FlyTime",0,fly)
    ws("Player_Y",0,flap>0 and 0x40 or 0x10) ws("Player_YHi",0,flap>0 and 1 or 0) ws("Player_YVel",0,0) ws("Player_InAir",0,1)
  end
  local yv=(rs("Player_YVel")+128)%256-128
  local y=rs("Player_YHi")*256+rs("Player_Y")
  if f>10+flap and rs("Player_InAir")~=0 and prev and y<prev then rises=rises+1 end
  prev=y
  if f%4==0 then log(string.format("f=%d py=%d yv=%d air=%d suit=%d hp=%d dying=%d vs=%d sy=%d px=%d xv=%d duck=%d slide=%d wag=%d",f,y,yv,rs("Player_InAir"),rs("Player_Suit"),rs("Gim_Health"),rs("Player_IsDying"),rs("Vert_Scroll"),rs("Player_SpriteY"),rs("Player_XHi")*256+rs("Player_X"),(rs("Player_XVel")+128)%256-128,rs("Player_IsDucking"),rs("Player_Slide"),rs("Player_WagCount"))) end
  if f>=dur then log("frames rising while falling: "..rises) quit() end
end
