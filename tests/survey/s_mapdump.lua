-- Print part of stage 1's map, screen 1: # solid, T tube, ~ water, x lethal.
FRAME = function(f)
  if f == 2 then
    for x = 0x34, 0x44 do
      local s = string.format("x=%02x ", x)
      for row = 0, 11 do
        local t = tile(x, 0x10 + row)
        local a = r(0x7E00 + t)
        s = s .. (a == 0x30 and "T" or (a >= 0x80 and "#" or (r(0x7D00 + t) == 0 and "x" or ".")))
      end
      log(s .. "   attrs " .. string.format("%02x %02x %02x", r(0x7E00 + tile(x, 0x19)), r(0x7E00 + tile(x, 0x1A)), r(0x7E00 + tile(x, 0x1B))))
    end
    done()
  end
end
