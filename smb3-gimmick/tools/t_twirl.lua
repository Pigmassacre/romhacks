dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
INPUT=function(f)
  if f>=120 and f<125 then return {start=true} end
  if f>=200 and f<205 then return {start=true} end
  return {}
end
FRAME=function(f)
  if f>=640 then ws("World_Map_Twirl",0,1) end
  if f>=650 and f<658 then shot("tw_"..(f-650)..".png") end
  if f==660 then quit() end
end
