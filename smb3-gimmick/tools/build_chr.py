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


# The Ohagi, Gimmick's black blob, on its page: left and right halves, facing left like Yumetaro
OH_PAGE = 0x0A
OH_L, OH_R = pair(OH_PAGE, 0x00), pair(OH_PAGE, 0x10)	# stands
OH_L1, OH_R1 = pair(OH_PAGE, 0x02), pair(OH_PAGE, 0x12)	# one foot
OH_L2, OH_R2 = pair(OH_PAGE, 0x04), pair(OH_PAGE, 0x14)	# the other
OH_BLINK = pair(OH_PAGE, 0x06)
BLANK = bytes(32)

# Its pages have Yumetaro's layout, so his frames draw it: what goes over each of his tiles, and blank for his horn
OHAGI_TILES = {
    0x0C: {0x04: OH_L, 0x14: OH_R, 0x06: OH_BLINK, 0x16: OH_R, 0x08: OH_L, 0x18: OH_R, 0x0A: OH_L1, 0x1A: OH_R1,
           0x0C: OH_L, 0x1C: OH_R, 0x0E: OH_L, 0x1E: OH_R, 0x20: OH_L2, 0x30: OH_R2, 0x22: OH_L, 0x24: OH_L2,
           0x34: OH_R2, 0x26: OH_L, 0x36: OH_R, 0x00: BLANK, 0x02: BLANK, 0x10: BLANK, 0x12: BLANK, 0x32: BLANK},
    0x0D: {0x20: OH_BLINK, 0x30: OH_R, 0x22: OH_BLINK, 0x32: OH_R, 0x02: BLANK, 0x0E: BLANK},
}


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


def build_ohagi(src_page):
    data = bytearray(build(src_page))
    for tile, gfx in OHAGI_TILES[src_page].items():
        data[tile * 16:tile * 16 + 32] = gfx
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


def split16(rows):
    """Four tiles' worth of a 16x16 panel, as the map's layout orders them: UL, LL, UR, LR."""
    ul = [r[:8] for r in rows[:8]]
    ur = [r[8:] for r in rows[:8]]
    ll = [r[:8] for r in rows[8:]]
    lr = [r[8:] for r in rows[8:]]
    return glyph(ul), glyph(ll), glyph(ur), glyph(lr)


PANEL_O = split16([
    "................", ".++++++++++++++.", ".++++++++++++++.", ".++.........+++.",
    ".++.@@@@@@@@.++.", ".++.@@....@@.++.", ".++.@@.++.@@.++.", ".++.@@.++.@@.++.",
    ".++.@@.++.@@.++.", ".++.@@....@@.++.", ".++.@@@@@@@@.++.", ".++..........++.",
    ".++++++++++++++.", ".++++++++++++++.", ".++++++++++++++.", "................",
])

MAP_TILES += [
    # The map's markers for whose turn it isn't: a Y and an O in a circle, as an 8x16 sprite
    (0x21, 0x22, glyph(["........", "........", "..@@@@..", ".@####@.", "@######@", "@@####@@", "@#@##@#@", "@##@@##@"])),
    (0x21, 0x23, glyph(["@##@@##@", "@##@@##@", "@######@", ".@####@.", "..@@@@..", "........", "........", "........"])),
    (0x21, 0x0E, glyph(["........", "........", "..@@@@..", ".@####@.", "@######@", "@##@@##@", "@#@##@#@", "@#@##@#@"])),
    (0x21, 0x0F, glyph(["@#@##@#@", "@##@@##@", "@######@", ".@####@.", "..@@@@..", "........", "........", "........"])),
    # The H of OHAGI, in a tile the map doesn't use ($D3)
    (0x17, 0x13, glyph(["########", "#++##++#", "#++##++#", "#++++++#", "#++##++#", "#++##++#", "#++##++#", "########"])),
    # A panel the second player cleared
    (0x17, 0x1C, PANEL_O[0]), (0x17, 0x1D, PANEL_O[1]), (0x17, 0x1E, PANEL_O[2]), (0x17, 0x1F, PANEL_O[3]),
    # The status bar's <O>
    (0x5D, 0x36, glyph(["@@@@@@@@", "@#######", "##@@#+++", "#@@@#++#", "#@@@#++#", "#@@@#++#", "##@@#+++", "@#######"])),
    (0x5D, 0x37, glyph(["@@@@@@@@", "#######@", "+++#@@##", "#++#@@@#", "#++#@@@#", "#++#@@@#", "+++#@@##", "#######@"])),
    # The battle's status boxes: Y and O for M and L
    (0x58, 0x2A, glyph(["+@...+@.", "+@...+@.", ".+@.+@..", "..+@@...", "...+@...", "...+@...", "...+@...", "...+@..."])),
    (0x58, 0x2B, glyph([".+@@@@..", "+@...+@.", "+@...+@.", "+@...+@.", "+@...+@.", "+@...+@.", "+@...+@.", ".+@@@@.."])),
    # The battle's players: his frames over Mario's, in the order of Vs_PlayerSprPats
    (0x07, 0x04, pair(0x0C, 0x04)), (0x07, 0x06, pair(0x0C, 0x14)),	# stand
    (0x07, 0x00, pair(0x0C, 0x08)), (0x07, 0x02, pair(0x0C, 0x18)),	# walk
    (0x07, 0x10, pair(0x0C, 0x0A)), (0x07, 0x12, pair(0x0C, 0x1A)),	# skid
    (0x07, 0x0C, pair(0x0C, 0x24)), (0x07, 0x0E, pair(0x0C, 0x34)),	# jump
    (0x07, 0x08, pair(0x0D, 0x20)), (0x07, 0x0A, pair(0x0D, 0x30)),	# dizzy
    (0x07, 0x14, pair(0x0C, 0x0E)), (0x07, 0x16, pair(0x0C, 0x1E)),	# kick
    (0x07, 0x18, pair(0x0D, 0x1E)),					# dying, mirrored
    (0x07, 0x1A, pair(0x0C, 0x04)), (0x07, 0x1C, pair(0x0C, 0x14)),	# climb
    (0x04, 0x30, pair(0x0C, 0x02)),					# horn
    # The Ohagi in battle, in tiles nothing there draws, in the order of Vs_PlayerSprPats' second half
    (0x07, 0x1E, OH_L), (0x07, 0x22, OH_R), (0x07, 0x24, OH_L1), (0x07, 0x34, OH_R1),
    (0x07, 0x36, OH_L2), (0x07, 0x38, OH_R2), (0x07, 0x3A, OH_BLINK),
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

for out_page, src_page in ((0x40, 0x0C), (0x41, 0x0D)):
    with open(os.path.join(OUT, 'chr%03d.bin' % out_page), 'wb') as f:
        f.write(build_ohagi(src_page))

pages = {}
for page, tile, data in MAP_TILES:
    if page not in pages:
        with open(os.path.join(ROOT, 'src', 'CHR', 'chr%03d.bin' % page), 'rb') as f:
            pages[page] = bytearray(f.read())
    pages[page][tile * 16:tile * 16 + len(data)] = data

# The map's sprite pages again with the Ohagi in Yumetaro's tiles, swapped in on its turn; both must be pages nothing
# else needs ($40-$43 were Tanooki Mario's)
for out_page, src_page, tiles in (
    (0x42, 0x20, ((0x2C, OH_L), (0x2E, OH_R), (0x0C, OH_L2), (0x0E, OH_R2), (0x3C, OH_L1), (0x3E, OH_R1))),
    (0x43, 0x21, ((0x08, BLANK),)),
):
    pages[out_page] = bytearray(pages[src_page])
    for tile, gfx in tiles:
        pages[out_page][tile * 16:tile * 16 + 32] = gfx

for page, chr_data in pages.items():
    with open(os.path.join(OUT, 'chr%03d.bin' % page), 'wb') as f:
        f.write(chr_data)
