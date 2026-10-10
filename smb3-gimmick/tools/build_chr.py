import os
from nes import load_rom

ROOT = os.path.join(os.path.dirname(__file__), '..')
_, gchr = load_rom(os.path.join(ROOT, 'Gimmick! (Japan).nes'))

EXTRA = [(0x28, 0x08, 0x00), (0x2A, 0x08, 0x10), (0x2C, 0x0C, 0x2E), (0x38, 0x0C, 0x3E)]


def pair(page, tile):
    o = page * 1024 + tile * 16
    return gchr[o:o + 32]


def build(src_page):
    data = bytearray(gchr[src_page * 1024:(src_page + 1) * 1024])
    for dst, page, tile in EXTRA:
        data[dst * 16:dst * 16 + 32] = pair(page, tile)
    return bytes(data)


def mirror(data):
    return bytes(int('{:08b}'.format(b)[::-1], 2) for b in data)


def color3_to_2(data):
    out = bytearray(data)
    for t in range(0, len(out), 16):
        for y in range(8):
            out[t + y] &= ~out[t + 8 + y] & 0xFF
    return bytes(out)


MAP_TILES = [
    (0x20, 0x2C, pair(0x0C, 0x04)),
    (0x20, 0x2E, pair(0x0C, 0x14)),
    (0x20, 0x0C, pair(0x0C, 0x0A)),
    (0x20, 0x0E, pair(0x0C, 0x1A)),
    (0x20, 0x3C, mirror(pair(0x0C, 0x14))),
    (0x20, 0x3E, mirror(pair(0x0C, 0x04))),
    (0x21, 0x08, color3_to_2(pair(0x0C, 0x02))),
]


for out_page, src_page in ((0x50, 0x0C), (0x51, 0x0D)):
    with open(os.path.join(ROOT, 'src', 'CHR', 'chr%03d.bin' % out_page), 'wb') as f:
        f.write(build(src_page))

for page, tile, data in MAP_TILES:
    path = os.path.join(ROOT, 'src', 'CHR', 'chr%03d.bin' % page)
    with open(path, 'rb') as f:
        chr_data = bytearray(f.read())
    chr_data[tile * 16:tile * 16 + 32] = data
    with open(path, 'wb') as f:
        f.write(chr_data)
