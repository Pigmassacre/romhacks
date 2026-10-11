import sys
d = open(sys.argv[1], 'rb').read()
attr, vert, ram = d[:8], d[8], d[9:]
r0, r1 = int(sys.argv[2]), int(sys.argv[3])
hexm = len(sys.argv) > 4
def ch(v):
    if hexm: return '%02X' % v
    q = v >> 6
    return '#' if v >= attr[q + 4] else '=' if v >= attr[q] else '.'
if vert:
    for row in range(r0, r1):
        print('%3d ' % row + ''.join(ch(ram[row * 16 + c]) for c in range(16)))
else:
    for row in range(27):
        print('%2d ' % row + ''.join(ch(ram[s * 0x1B0 + row * 16 + c]) for s in range(r0, r1) for c in range(16)))
