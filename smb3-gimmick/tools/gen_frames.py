import os
from nes import load_rom

ROOT = os.path.join(os.path.dirname(__file__), '..')
prg, _ = load_rom(os.path.join(ROOT, 'Gimmick! (Japan).nes'))
BANK = 15 * 0x4000
PAGE_MAP = {0x0C: 0x50, 0x0D: 0x51}
NFRAMES = 22


def rd(a):
    return prg[BANK + a - 0x8000]


def s8(v):
    return v - 256 if v > 127 else v


def frame_sprites(i):
    p = rd(0x843D + 2 * i) | rd(0x843D + 2 * i + 1) << 8
    out = []
    while rd(p) != 0:
        out.append((s8(rd(p)), rd(p + 1), rd(p + 2), s8(rd(p + 3))))
        p += 4
    return out


def main():
    lines = []
    ptr_l, ptr_h, pages, bodies = [], [], [], []
    for i in range(NFRAMES):
        spr = frame_sprites(i)
        bottom = [s for s in spr if s[0] >= -24]
        top = [s for s in spr if s[0] < -24]
        assert len(bottom) <= 3 and len(top) <= 3, (i, spr)
        hidden = (0, 0xF1, 0, 0)
        slots = bottom + [hidden] * (3 - len(bottom)) + top + [hidden] * (3 - len(top))
        data = []
        for dy, t, a, dx in slots:
            if t == 0xF1:
                data += [0, 0xF1, 0, 0]
                continue
            attr = (a & 0xC0) | (3 if a & 1 else 0)
            data += [(dy + 33) & 0xFF, t | 1, attr, dx & 0xFF]
        ptr_l.append('LOW(GimF%02d)' % i)
        ptr_h.append('HIGH(GimF%02d)' % i)
        pages.append('$%02X' % PAGE_MAP[rd(0x85CE + i)])
        bodies.append('GimF%02d:\t.byte %s' % (i, ', '.join('$%02X' % b for b in data)))
    lines.append('GimFrame_PtrL:\t.byte ' + ', '.join(ptr_l))
    lines.append('GimFrame_PtrH:\t.byte ' + ', '.join(ptr_h))
    lines.append('GimFrame_Page:\t.byte ' + ', '.join(pages))
    lines += bodies
    with open(os.path.join(ROOT, 'src', 'PRG', 'gim_frames.asm'), 'w') as f:
        f.write('\n'.join(lines) + '\n')


main()
