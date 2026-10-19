local OUT="/home/olof/dev/romhacks/smb3-gimmick/out/"
local M=emu.memType.nesMemory
local function r(a) return emu.read(a,M) end
local f=0
local log=io.open(OUT.."gim_trace.csv","w")
local writers={}
-- input script: list of {startFrame,endFrame,buttons}
local script={
 {700,760,{right=true}},
 {800,830,{left=true}},
 {860,862,{a=true}},          -- short jump tap
 {920,960,{a=true}},          -- long jump hold
 {1000,1040,{right=true,a=true}},
 {1100,1170,{b=true}},        -- charge star, release throw
 {1240,1300,{b=true,right=true}},
 {1300,1330,{right=true}},
}
emu.addEventCallback(function()
  local inp={}
  if f<560 and r(0x90)==0 then inp.start=(f%60)<5 end
  for _,s in ipairs(script) do if f>=s[1] and f<s[2] then for k,v in pairs(s[3]) do inp[k]=v end end end
  emu.setInput(inp,0)
end, emu.eventType.inputPolled)
local function watch(addr,name)
  emu.addMemoryCallback(function(a,v)
    if f<650 then return end
    local pc=emu.getState()["cpu.pc"]
    local ab=emu.getPrgRomOffset and emu.getPrgRomOffset(pc) or -1
    local key=name.." "..string.format("%04X b40=%02X b41=%02X",pc,r(0x40),r(0x41))
    writers[key]=(writers[key] or 0)+1
  end, emu.callbackType.write, addr, addr)
end
for _,w in ipairs({{0x91,"st1"},{0x0393,"tmr2_1"},{0x0383,"tmr1_1"},{0xCC,"xspd"},{0xC2,"yspd"},{0x4B,"jhold"},{0x55,"btimer"},{0x91,"st1"},{0xCD,"xspd1"},{0xC3,"yspd1"},{0x53,"floor"}}) do watch(w[1],w[2]) end
emu.addEventCallback(function()
  f=f+1
  if f>=650 then
    log:write(string.format("%d,%02x,%02x%02x,%02x%02x,%d,%d,%02x,%02x,%02x,%02x,%02x%02x,%02x%02x,%d,%d,%02x\n",f,r(0x90),r(0xB8),r(0xAE),r(0xA4),r(0x9A),
      (r(0xCC)>127) and r(0xCC)-256 or r(0xCC),(r(0xC2)>127) and r(0xC2)-256 or r(0xC2),r(0x4B),r(0x53),r(0x55),r(0x91),
      r(0xB9),r(0xAF),r(0xA5),r(0x9B),(r(0xCD)>127) and r(0xCD)-256 or r(0xCD),(r(0xC3)>127) and r(0xC3)-256 or r(0xC3),r(0xF7)))
  end
  if f==1150 or f==1180 or f==1200 then local h=io.open(OUT..string.format("gt_%d.png",f),"wb"); h:write(emu.takeScreenshot()); h:close() end
  if f==1400 then
    local w=io.open(OUT.."gim_writers.txt","w")
    for k,v in pairs(writers) do w:write(k.." "..v.."\n") end
    w:close(); log:close(); emu.stop(0)
  end
end, emu.eventType.endFrame)
