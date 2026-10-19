-- Grabs the wand in a Koopaling room and plays on into the king's room. Yumetaro must fall in, then stand still
dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."lv_W1BOSS.mss")
local landed,walk,king=0,0,false
emu.addMemoryCallback(function() if rs("PAGE_A000")==27 then king=true end end, emu.callbackType.exec, S["CineKing_DoWandReturn"], S["CineKing_DoWandReturn"])
-- What Player_Draw is about to draw: Gim_Frame if Gim_Animated, else a frame mapped from Player_Frame
local drawn=nil
emu.addMemoryCallback(function() if rs("PAGE_C000")==29 then drawn=(rs("Gim_Animated")~=0) and rs("Gim_Frame") or -1 end end, emu.callbackType.exec, S["PRG029_CF1E"], S["PRG029_CF1E"])
FRAME=function(f)
  if not king then ws("Player_FlashInv",0,0x10) end
  if f==150 then ws("Level_GetWandState",0,3) end
  local st,t=rs("CineKing_State"),rs("Level_Tileset")
  local y=rs("Player_YHi")*256+rs("Player_Y")
  if king and rs("Player_Frame")==0x3E then
    landed=landed+1
    if drawn~=0 then walk=walk+1 end
    if landed==20 or landed==37 or landed==90 then shot(string.format("king_%03d.png",landed)) end
  end
  if f%30==0 or (king and landed<40) then log(string.format("f=%d wand=%d ts=%d king=%d py=%d pf=%02x gf=%d anim=%d",f,rs("Level_GetWandState"),t,st,y,rs("Player_Frame"),rs("Gim_Frame"),rs("Gim_Animated"))) end
  if landed>=200 or f>4000 then log(string.format("frames landed: %d, not standing: %d",landed,walk)) quit() end
end
