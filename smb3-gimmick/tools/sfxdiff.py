import sys
lo, hi = int(sys.argv[1]), int(sys.argv[2])
apu = {}
b5 = {}
sel = 0
frames = {}
for line in open('/home/olof/dev/smb3-gimmick/out/gim_sfx.log'):
    p = line.split()
    f = int(p[0])
    if p[1] == 'SFX':
        frames.setdefault(f, []).append('SFX ' + p[2])
        continue
    a, v = p[2].split('=')
    a = int(a, 16)
    v = int(v, 16)
    if p[1] == 'W':
        if a in (0x4014, 0x4016, 0x4017):
            continue
        old = apu.get(a)
        apu[a] = v
        if old != v and lo <= f <= hi:
            frames.setdefault(f, []).append('%04x=%02x' % (a, v))
    else:
        if a == 0xC000:
            sel = v
            continue
        old = b5.get(sel)
        b5[sel] = v
        if old != v and lo <= f <= hi:
            frames.setdefault(f, []).append('5B[%x]=%02x' % (sel, v))
for f in sorted(frames):
    if lo <= f <= hi:
        print(f, ' '.join(frames[f]))
