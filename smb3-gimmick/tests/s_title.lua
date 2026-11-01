-- The title screen left to run, with screenshots, for looking over.
FRAME = function(f)
  if f % 150 == 0 then shot(string.format("%05d", f)) end
  if f == 150*30 then done() end
end
