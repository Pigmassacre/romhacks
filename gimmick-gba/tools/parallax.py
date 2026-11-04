"""The game's graphics as GBA tiles, with what parallax clouds need, the way the SNES
port does them: tools/recomp.py writes out/gen/chr4.bin and out/gen/parallax.bin.

Stages 1, 2 and 4 have sky and clouds behind them, drawn as tiles. Sky and clouds move to
a layer of their own, at the back, at half the camera's speed, and the stage's own sky
and cloud tiles go blank in a version of their pages. On that layer the NES's colour 0,
see-through, is the sky's colour 1. A third layer, between the two, is a mask: the sky's colour
wherever the NES shows its colour 0 outside the sky, as in the gaps of a wall, so that
the clouds only show where the NES shows sky. Sprites behind the background go between
the stage and the mask, where the NES shows them.

chr4.bin is the 128 pages of 64 tiles, then those versions, then a mask of each page.

The same tiles are also the stage's own, in its other palettes: the ship of stage 2 is
built from the sky's solid tile and its clouds' patterns. So a sky tile only goes blank
where its palette's colour 1 is the sky's, and parallax.bin keeps the sky tiles as they
are, for the cells drawn in other colours.
"""
import struct

PAGES = 128
CLOUD_PAGE, FILL_PAGE = 0x01, 0x00

# The clouds: the game's own page of them, arranged as it does in stage 1 and in stages
# 2 and 4. An entry is a tile of that page; L and W are its fill tiles.
PUFFS = {
    3: {5: (0x09, 0x06, 0x16, 0x07, 0x17, 0x08, 0x18)},
    6: {0: (0x02, 0x12, 0x04, 0x14), 30: (0x00, 0x10)},
    7: {0: (0x03, 0x13, 0x05, 0x15, 0x08, 0x18), 13: (0x09, 0x08, 0x18), 29: (0x09, 0x01, 0x11)},
    9: {9: (0x09, 0x06, 0x16, 0x07)},
    11: {21: (0x09, 0x06, 0x16, 0x07, 0x17)},
}
# The bank of cloud under them: the rows the title screen has, which meet at their ends,
# so it loops.
CLOUD_BANK = {
    15: {0: (0x0A, 0x1A, 0x0B, 0x1B, 0x0A, 0x1A, 0x0B, 0x1B, 0x0A, 0x1A, 0x0B, 0x1B, 0x0A, 0x1A, 0x2B, 0x3B,
             0x0A, 0x1A, 0x0B, 0x1B, 0x0C, 0x1C, 0x0D, 0x1D, 0x0E, 0x1E, 0x0B, 0x1B, 0x0A, 0x1A, 0x0B, 0x1B)},
    16: {0: ("L",) * 11 + (0x38, 0x2A, 0x3A, "W", "W", 0x2C) + ("L",) * 15},
    17: {0: (0x24, 0x34, 0x25, 0x35) + ("L",) * 6 + (0x29,) + ("W",) * 6 + (0x3D,) + ("L",) * 14},
    18: {0: (0x20, 0x23, 0x23, 0x33, 0x20, 0x23, 0x22, 0x32, 0x20, 0x23) + ("W",) * 8 + (0x20, 0x23) * 7},
}
FILL_ROW = 19               # the bank's fill goes on down from here
TILE_L, TILE_W, TILE_SKY = 64, 65, 66

# The sky and cloud tiles of the pages these stages use. All of the clouds' page but the
# shadows under platforms, on the walls' triangles, which are foreground.
CLOUD_TILES = set(range(64)) - {0x0F, 0x21, 0x28, 0x30, 0x31, 0x39}
# Slopes have the white of the clouds behind them in their tiles, as colour 3. In this
# page's first four columns are the walls, whose white is their own.
SLOPE_TILES = {0x02: {t for t in range(64) if t & 15 >= 4}}
SKY = {0x00: (0x10, 0x11, 0x01), 0x23: (0x10, 0x11, 0x01), 0x36: (0x01,), 0x34: (0x01,),
       CLOUD_PAGE: CLOUD_TILES}

# For each stage ($1B): which cloud map (1 with the bank, 2 the puffs alone, 3 the bank
# over the sea), the NES palette its clouds use, and the line of the map at the top of
# the NES's screen. Stage 2's sea is a row of waves on the NES's row 22 and its light
# colour under them, so there the bank's last row is behind the waves and the fill under
# it is that colour.
STAGES = {0: (1, 1, 7), 1: (3, 1, 7 - 39), 3: (2, 3, 7)}


def tile_4bpp(chr16, pixel=lambda p: p):
    """A NES tile, 16 bytes, as a GBA one, 32. pixel maps each NES colour to the GBA's."""
    out = bytearray(32)
    for y in range(8):
        lo, hi = chr16[y], chr16[8 + y]
        row = 0
        for x in range(8):
            row |= pixel((lo >> (7 - x) & 1) | (hi >> (7 - x) & 1) << 1) << (x * 4)
        out[y * 4:y * 4 + 4] = struct.pack("<I", row)
    return bytes(out)


def page_tiles(chr_rom, page):
    return [chr_rom[page * 0x400 + t * 16:page * 0x400 + t * 16 + 16] for t in range(64)]


def cloud_map(tables, fill_from, fill=TILE_W):
    out = [[TILE_SKY] * 32 for _ in range(32)]
    for table in tables:
        for r, parts in table.items():
            for c, seq in parts.items():
                for i, v in enumerate(seq):
                    out[r][(c + i) % 32] = TILE_L if v == "L" else TILE_W if v == "W" else v
    if fill_from is not None:
        for r in range(fill_from, 22):
            out[r] = [fill] * 32
    return bytes(v for row in out for v in row)


def build(chr_rom):
    """(chr4.bin, parallax.bin)"""
    chr4 = bytearray()
    for p in range(PAGES):
        for t in page_tiles(chr_rom, p):
            chr4 += tile_4bpp(t)
    # The stage's tiles, with sky and clouds blank and the white behind slopes gone.
    alias = [0xFF] * PAGES
    for p in sorted(set(SKY) | set(SLOPE_TILES)):
        alias[p] = len(chr4) // 0x800
        for i, t in enumerate(page_tiles(chr_rom, p)):
            if i in SKY.get(p, ()):
                chr4 += bytes(32)
            elif i in SLOPE_TILES.get(p, ()):
                chr4 += tile_4bpp(t, lambda c: 0 if c == 3 else c)
            else:
                chr4 += tile_4bpp(t)
    # The masks: colour 15, the sky's, where the NES has colour 0, but not in the sky.
    mask_base = len(chr4) // 0x800
    for p in range(PAGES):
        for i, t in enumerate(page_tiles(chr_rom, p)):
            if i in SKY.get(p, ()):
                chr4 += bytes(32)
            else:
                chr4 += tile_4bpp(t, lambda c: 15 if c == 0 else 0)

    def solid(t):
        return tile_4bpp(t, lambda c: c or 1)

    clouds = bytearray()
    for t in page_tiles(chr_rom, CLOUD_PAGE):
        clouds += solid(t)
    fill = page_tiles(chr_rom, FILL_PAGE)
    clouds += solid(fill[0x11]) + solid(fill[0x01]) + solid(bytes(16))
    maps = (cloud_map([PUFFS, CLOUD_BANK], FILL_ROW) + cloud_map([PUFFS], None)
            + cloud_map([PUFFS, CLOUD_BANK], FILL_ROW, TILE_L))

    # Each version's sky tiles as they are: per version 64 bytes, the number of each of
    # its sky tiles among these (0xFF for the others), then the tiles.
    index, kept = bytearray(), bytearray()
    for p in sorted(set(SKY) | set(SLOPE_TILES)):
        for i, t in enumerate(page_tiles(chr_rom, p)):
            if i in SKY.get(p, ()):
                index.append(len(kept) // 32)
                kept += tile_4bpp(t)
            else:
                index.append(0xFF)

    # alias[128], mask_base, 3 spare, then per stage (8): map, palette, top line (s16),
    # then at 256 the cloud tiles, at 256 + 67 * 32 their three maps, and after those the
    # sky tiles as they are.
    head = bytearray(bytes(alias) + bytes([mask_base, 0, 0, 0]))
    for s in range(8):
        m, pal, y = STAGES.get(s, (0, 0, 0))
        head += struct.pack("<BBh", m, pal, y)
    head += bytes(256 - len(head))
    return bytes(chr4), bytes(head + clouds + maps + index + kept)
