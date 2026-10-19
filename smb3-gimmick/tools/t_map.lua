dofile("/home/olof/dev/romhacks/smb3-gimmick/tools/lib.lua")
INPUT=function(f)
  if f>=120 and f<125 then return {start=true} end
  if f>=200 and f<205 then return {start=true} end
  if f>=700 and f<760 and f%40<4 then return {right=true} end
  return {}
end
FRAME=function(f)
  if f==650 then shot("map_a.png") end
  if f==658 then shot("map_b.png") end
  if f==720 then shot("map_c.png") end
  if f==800 then shot("map_d.png") end
  if f==802 then quit() end
end
