-- Holds B through a Koopaling room; from frame 150 pretends the wand was grabbed. The star must vanish and stay away
dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."lv_W1BOSS.mss")
INPUT=function(f) return {b=(f%80)<60} end
local seen=0
FRAME=function(f)
  ws("Player_FlashInv",0,0x10)
  if f==150 then ws("Level_GetWandState",0,3) end
  if f>150 and rs("Star_State")~=0 then seen=seen+1 end
  if f%30==0 then log(string.format("f=%d wand=%d star=%02x py=%d",f,rs("Level_GetWandState"),rs("Star_State"),rs("Player_YHi")*256+rs("Player_Y"))) end
  if f==400 then log("star frames after the wand: "..seen) quit() end
end
