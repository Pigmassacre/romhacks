-- Screenshots of the recall effect, one per frame (not a pass/fail test).
INPUT = function(f)
  if f <= 40 then return pad("B") end
  if f >= 61 and f <= 100 then return pad("B") end
  return {}
end
FRAME = function(f)
  if f >= 59 and f <= 78 then shot(string.format("%03d", f)) end
  if f == 79 then done() end
end
