OUT="/home/olof/dev/romhacks/smb3-gimmick/out/"
M=emu.memType.nesMemory
function r(a) return emu.read(a,M) end
function r16(hi,lo) return r(hi)*256+r(lo) end
function shot(name) local g=io.open(OUT..name,"wb"); g:write(emu.takeScreenshot()); g:close() end
LOG=io.open(OUT.."lua.log","w")
function log(s) LOG:write(s.."\n"); LOG:flush() end
S={}
for line in io.lines(OUT.."smb3.fns") do
  local n,v=line:match("^(%S+)%s+=%s+%$(%x+)")
  if n then S[n]=tonumber(v,16) end
end
function rs(name,o) return r(S[name]+(o or 0)) end
function ws(name,o,v) emu.write(S[name]+o,v%256,M) end
F=0
INPUT=function(f) return {} end
FRAME=function(f) end
local function onExec(fn)
  local id
  id=emu.addMemoryCallback(function()
    emu.removeMemoryCallback(id, emu.callbackType.exec, 0x8000, 0xFFFF)
    fn()
  end, emu.callbackType.exec, 0x8000, 0xFFFF)
end
function loadstate(path)
  local h=io.open(path,"rb"); local s=h:read("a"); h:close()
  onExec(function() emu.loadSavestate(s); F=0 end)
end
function savestate(path)
  onExec(function() local s=emu.createSavestate(); local h=io.open(path,"wb"); h:write(s); h:close() end)
end
function quit() LOG:close(); emu.stop(0) end
function warp(name)
  local w,ts,lay,obj
  for line in io.lines(OUT.."levels.txt") do
    local n,a,b,c,d=line:match("^(%S+) (%d+) (%d+) (%d+) (%d+)")
    if n==name then w,ts,lay,obj=tonumber(a),tonumber(b),tonumber(c),tonumber(d) end
  end
  assert(w, "unknown level "..name)
  emu.addMemoryCallback(function()
    ws("World_Num",0,w) ws("Level_Tileset",0,ts)
    ws("Level_LayPtr_AddrL",0,lay) ws("Level_LayPtr_AddrH",0,lay>>8)
    ws("Level_LayPtrOrig_AddrL",0,lay) ws("Level_LayPtrOrig_AddrH",0,lay>>8)
    ws("Level_ObjPtr_AddrL",0,obj) ws("Level_ObjPtr_AddrH",0,obj>>8)
    ws("Level_ObjPtrOrig_AddrL",0,obj) ws("Level_ObjPtrOrig_AddrH",0,obj>>8)
  end, emu.callbackType.exec, S["PRG030_892A"], S["PRG030_892A"])
end
emu.addEventCallback(function() emu.setInput(INPUT(F),0) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  F=F+1
  local ok,err=pcall(FRAME,F)
  if not ok then log("ERR "..tostring(err)); quit() end
end, emu.eventType.endFrame)
