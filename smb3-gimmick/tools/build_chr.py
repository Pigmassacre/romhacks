import os
from nes import load_rom

ROOT = os.path.join(os.path.dirname(__file__), '..')
_, gchr = load_rom(os.path.join(ROOT, 'Gimmick! (Japan).nes'))
_, schr = load_rom(os.path.join(ROOT, 'Super Mario Bros III.nes'))

EXTRA = [(0x28, 0x08, 0x00), (0x2A, 0x08, 0x10)]

# Must match MOVED in gen_frames.py
MOVED = {0x0D: [(0x2E, 0x00)]}

# SMB3's splash and bubble tiles, which it draws from the player page; must match Splash_Patterns and BUBBLE_TILE
SMB3_SHARED = [(0x2C, 0x10), (0x2E, 0x12), (0x38, 0x14), (0x3C, 0x16)]


def pair(page, tile):
    o = page * 1024 + tile * 16
    return gchr[o:o + 32]


def build(src_page):
    data = bytearray(gchr[src_page * 1024:(src_page + 1) * 1024])
    for dst, page, tile in EXTRA:
        data[dst * 16:dst * 16 + 32] = pair(page, tile)
    for src, dst in MOVED.get(src_page, []):
        data[dst * 16:dst * 16 + 32] = pair(src_page, src)
    for dst, src in SMB3_SHARED:
        o = 0x50 * 1024 + src * 16
        data[dst * 16:dst * 16 + 32] = schr[o:o + 32]
    return bytes(data)


def mirror(data):
    return bytes(int('{:08b}'.format(b)[::-1], 2) for b in data)


def color3_to_2(data):
    out = bytearray(data)
    for t in range(0, len(out), 16):
        for y in range(8):
            out[t + y] &= ~out[t + 8 + y] & 0xFF
    return bytes(out)


def horn(data):
    # On the map his horn shares palette 2: orange (2) and, in place of the level's dark outline, black (3)
    out = bytearray(data)
    for t in range(0, len(out), 16):
        for y in range(8):
            lo, hi = out[t + y], out[t + 8 + y]
            one, three = lo & ~hi & 0xFF, lo & hi
            out[t + y] = one
            out[t + 8 + y] = one | three
    return bytes(out)


MAP_TILES = [
    (0x20, 0x2C, pair(0x0C, 0x04)),
    (0x20, 0x2E, pair(0x0C, 0x14)),
    (0x20, 0x0C, pair(0x0C, 0x0A)),
    (0x20, 0x0E, pair(0x0C, 0x1A)),
    (0x20, 0x3C, mirror(pair(0x0C, 0x14))),
    (0x20, 0x3E, mirror(pair(0x0C, 0x04))),
    (0x21, 0x08, horn(pair(0x0C, 0x02))),
]

# The Y of YUMETARO over a tile the map doesn't use ($CC), and the status bar's <Y> over <M>
def glyph(rows):
    out = bytearray(16)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            v = '.#+@'.index(ch)
            out[y] |= (v & 1) << (7 - x)
            out[8 + y] |= (v >> 1) << (7 - x)
    return bytes(out)


MAP_TILES += [
    (0x17, 0x0C, glyph(["########", "#++##++#", "#++##++#", "##++++##", "@##++##@", "@@#++#@@", "@@#++#@@", "@@####@@"])),
    # A cleared panel: Y for M (tiles are upper left, lower left, upper right, lower right)
    (0x16, 0x08, glyph(["........", ".+++++++", ".+++++++", ".+....++", ".+.@@.++", ".+.@@@.+", ".++.@@@.", ".+++.@@@"])),
    (0x16, 0x09, glyph([".++++.@@", ".++++.@@", ".++++.@@", ".++++.@@", ".++++...", ".+++++++", ".+++++++", "........"])),
    (0x16, 0x0A, glyph(["........", "+++++++.", "+++++++.", "+....++.", "+.@@.++.", ".@@@.++.", "@@@.+++.", "@@.++++."])),
    (0x16, 0x0B, glyph(["@.+++++.", "@.+++++.", "@.+++++.", "@.+++++.", "..+++++.", "+++++++.", "+++++++.", "........"])),
    (0x5D, 0x34, glyph(["@@@@@@@@", "@#######", "##@@#++#", "#@@@#++#", "#@@@##++", "#@@@@#++", "##@@@#++", "@#######"])),
    (0x5D, 0x35, glyph(["@@@@@@@@", "#######@", "#++#@@##", "#++#@@@#", "++##@@@#", "++#@@@@#", "++#@@@##", "#######@"])),
]


OUT = os.path.join(ROOT, 'out', 'chr')
os.makedirs(OUT, exist_ok=True)

for out_page, src_page in ((0x50, 0x0C), (0x51, 0x0D)):
    with open(os.path.join(OUT, 'chr%03d.bin' % out_page), 'wb') as f:
        f.write(build(src_page))

pages = {}
for page, tile, data in MAP_TILES:
    if page not in pages:
        with open(os.path.join(ROOT, 'src', 'CHR', 'chr%03d.bin' % page), 'rb') as f:
            pages[page] = bytearray(f.read())
    pages[page][tile * 16:tile * 16 + len(data)] = data
for page, chr_data in pages.items():
    with open(os.path.join(OUT, 'chr%03d.bin' % page), 'wb') as f:
        f.write(chr_data)
