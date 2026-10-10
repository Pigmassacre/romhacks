dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
INPUT=function(f) return {} end
FRAME=function(f)
  if f==10 then ws("Gim_Health",0,1) end
  if f==20 then ws("Player_QueueSuit",0,2) end
  if f==40 then ws("Player_QueueSuit",0,4) ws("Player_SuitLost",0,0x17) end
  if f>=8 and f<=70 and f%2==0 then
    log(string.format("f=%d hp=%d max=%d suit=%d lost=%d bank=%02x",f,rs("Gim_Health"),rs("Gim_MaxHealth"),rs("Player_Suit"),rs("Player_SuitLost"),rs("PatTable_BankSel",2)))
  end
  if f==15 or f==30 or f==48 or f==70 then shot(string.format("u_%03d.png",f)) end
  if f==70 then quit() end
end
