dofile("/home/olof/dev/smb3-gimmick/tools/lib.lua")
loadstate(OUT.."w11.mss")
FRAME=function(f)
  if f==5 then
    local s="pal"
    for i=0,31 do s=s..string.format(" %02x",emu.read(i,emu.memType.nesPaletteRam)) end
    log(s)
    s="spr"
    for i=0x28,0x3f do s=s..string.format(" %02x",emu.read(i,emu.memType.nesSpriteRam)) end
    log(s)
    log(string.format("bank %02x %02x %02x %02x %02x %02x",rs("PatTable_BankSel"),rs("PatTable_BankSel",1),rs("PatTable_BankSel",2),rs("PatTable_BankSel",3),rs("PatTable_BankSel",4),rs("PatTable_BankSel",5)))
    quit()
  end
end
