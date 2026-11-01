"""The title screen: "Gimmick! 1.5".

The title's top part is a white panel with the logo, stored as raw nametable
rows in bank $1B ($8242: rows 4-29, then the attribute table at $8582). Its
background CHR pages are set by `lda #` immediates at $808A-$8097.

This module widens the panel from columns 4-27 to 1-30, moves the logo 3
columns left, and draws "1.5" in the space that leaves, in the logo's black
brush style. The new tiles go into copies of the title's four CHR pages, so
nothing else that uses those pages changes.

It also writes "ROMHACK BY PIGMASSACRE" and "AI SLOP - DO NOT PLAY" on the sky
above the panel. The game fills rows 0-3 with sky rather than loading them, so
TitleNotice (src/main.asm) draws the rows from a table this module fills in.
Everything below the panel scrolls.

    python3 tools/title.py      # writes out/title.png, a preview from the ROM
"""
import math
import os

BANK = 0x2000
TITLE_BANK = 0x1B
NT_ADDR = 0x8242            # nametable row 4, column 0
NT_ROW0 = 4
ATTR_ADDR = 0x8582          # attribute table ($23C0)
CHR_IMM = (0x808B, 0x808F, 0x8093, 0x8097)   # lda #page for $E5-$E8 (PPU $1000-$1FFF)
OAM_ADDR = 0x819A           # the title's sprites; 0 and 1 hide behind the panel's
                            # white side margins
OLD_PAGES = (0x00, 0x65, 0x66, 0x67)

WHITE = 0x01                # colour 3 everywhere: white in every palette
SKY = 0x10
BOTTOM = 0xFF               # panel bottom margin: white, last line sky
BAR_L, BAR, BAR_R = 0xE8, 0xF3, 0xF8
BAR_FOOT = 0xF5
KANA = ((0x48, 0x49), (0x58, 0x59), (0x68, 0x69), (0x78, 0x79))   # ギ ミ ッ ク

PANEL = (1, 30)             # new panel columns (old: 4-27)
SHIFT = 3                   # the logo moves this many columns left
ART_COL, ART_ROW = 24, 8    # "1.5" goes in columns 24-29, rows 8-12
ART_W, ART_H = 48, 40

NOTICE = ("ROMHACK BY PIGMASSACRE", "AI SLOP - DO NOT PLAY")
NOTICE_BANK = 0x20
NOTICE_ADDR = 0xBF00        # NoticeRows in src/defs.asm
NOTICE_ROW = 1              # NOTICE_PPU in src/defs.asm


# ---- Drawing "1.5" -----------------------------------------------------------

def _strokes():
    """Brush strokes in pixels, as (points, radius) lists; baseline is y = 39."""
    s = []

    def line(x0, y0, x1, y1, r0, r1=None, n=40):
        r1 = r0 if r1 is None else r1
        s.append([(x0 + (x1 - x0) * t / n, y0 + (y1 - y0) * t / n, r0 + (r1 - r0) * t / n) for t in range(n + 1)])

    def arc(cx, cy, rx, ry, a0, a1, r0, r1=None, n=80):
        r1 = r0 if r1 is None else r1
        pts = []
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a), r0 + (r1 - r0) * i / n))
        s.append(pts)

    # 1: a flag and a stem
    line(5.0, 11.5, 10.6, 3.0, 2.0, 2.9)
    line(10.6, 3.0, 10.6, 36.5, 2.9, 2.9)
    # .: a round dot like the !'s
    line(19.8, 34.3, 19.8, 34.3, 4.6)
    # 5: top bar, stem, and a bowl whose end curls inward into a ball, the
    # way the G's does
    line(31.8, 4.0, 44.6, 2.6, 2.7, 2.3)
    line(31.8, 4.0, 30.9, 17.5, 2.8)
    arc(36.6, 26.6, 8.0, 9.9, -126, 150, 2.8, 2.7)
    arc(34.6, 30.4, 4.6, 4.6, 165, 290, 2.6, 2.3, n=40)
    line(36.4, 26.4, 36.4, 26.4, 2.9)
    return s


def art():
    """The 48x40 "1.5" as colour indices: 0 black, 1 dark grey, 2 light grey, 3 white."""
    ss = 4
    strokes = _strokes()
    out = []
    for y in range(ART_H):
        row = []
        for x in range(ART_W):
            hit = 0
            for sy in range(ss):
                for sx in range(ss):
                    px = x + (sx + 0.5) / ss
                    py = y + (sy + 0.5) / ss
                    if any((px - qx) ** 2 + (py - qy) ** 2 <= qr * qr for st in strokes for qx, qy, qr in st):
                        hit += 1
            c = hit / (ss * ss)
            row.append(0 if c >= 0.8 else 1 if c >= 0.5 else 2 if c >= 0.22 else 3)
        out.append(row)
    return out


# ---- Drawing the notice ------------------------------------------------------

FONT = {
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "-": [".....", ".....", ".....", ".###.", ".....", ".....", "....."],
    " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}


def notice_art():
    """The notice's lines as rows of colour indices, one tile per letter so that
    the lines share tiles: white letters with a black shadow, on the sky's colour 1."""
    cols = max(len(line) for line in NOTICE)
    out = [[1] * (cols * 8) for _ in range(len(NOTICE) * 8)]
    for ty, line in enumerate(NOTICE):
        for tx, c in enumerate(line):
            for y, glyph_row in enumerate(FONT[c]):
                for x, v in enumerate(glyph_row):
                    if v == "#":
                        out[ty * 8 + y + 1][tx * 8 + x + 2] = 0
            for y, glyph_row in enumerate(FONT[c]):
                for x, v in enumerate(glyph_row):
                    if v == "#":
                        out[ty * 8 + y][tx * 8 + x + 1] = 3
    return out


# ---- CHR -----------------------------------------------------------------------

def decode_tile(b):
    return [[((b[y] >> (7 - x)) & 1) | (((b[y + 8] >> (7 - x)) & 1) << 1) for x in range(8)] for y in range(8)]


def encode_tile(px):
    lo = bytearray(8)
    hi = bytearray(8)
    for y in range(8):
        for x in range(8):
            lo[y] |= (px[y][x] & 1) << (7 - x)
            hi[y] |= (px[y][x] >> 1) << (7 - x)
    return bytes(lo + hi)


# ---- The patch -----------------------------------------------------------------

def _off(bank, addr):
    return 16 + bank * BANK + (addr & 0x1FFF)


def patch(rom, chr_base, new_pages, copies):
    """Rebuild the title in rom (the expanded ROM, a bytearray).

    chr_base: file offset of CHR ROM in rom. new_pages: the 4 free 1 KB CHR
    pages to use. copies: list to append (target offset, original page) to, so
    the BPS writer can copy those pages from the original ROM.
    """
    nt_off = _off(TITLE_BANK, NT_ADDR)
    old = [list(rom[nt_off + r * 32:nt_off + r * 32 + 32]) for r in range(11)]   # rows 4-14

    # Copy the four pages and find the slots the title does not use.
    used = set()
    for r in range(26):
        used.update(rom[nt_off + r * 32:nt_off + r * 32 + 32])
    second = _off(TITLE_BANK, 0x84E2 + 0xE0)          # the second nametable's rows 15-29
    used.update(rom[second:second + 0x300 - 0x40])
    pages = []
    for old_p, new_p in zip(OLD_PAGES, new_pages):
        src = chr_base + old_p * 1024
        dst = chr_base + new_p * 1024
        rom[dst:dst + 1024] = rom[src:src + 1024]
        copies.append((dst, old_p))
        pages.append(dst)
    free = [t for t in range(0x100) if t not in used and t != 0]

    slots = {}

    def cut(a, blank_colour, blank):
        """Cut art into tiles, returning {(row, column): tile number}."""
        glyph = {}
        for ty in range(len(a) // 8):
            for tx in range(len(a[0]) // 8):
                px = [row[tx * 8:tx * 8 + 8] for row in a[ty * 8:ty * 8 + 8]]
                if all(v == blank_colour for r in px for v in r):
                    glyph[(ty, tx)] = blank
                    continue
                enc = encode_tile(px)
                if enc not in slots:
                    if not free:
                        raise SystemExit("title: out of free tiles")
                    t = free.pop(0)
                    slots[enc] = t
                    o = pages[t >> 6] + (t & 0x3F) * 16
                    rom[o:o + 16] = enc
                glyph[(ty, tx)] = slots[enc]
        return glyph

    # Cut "1.5" into tiles.
    glyph = cut(art(), 3, WHITE)

    # Cut the notice into tiles, and fill in the rows TitleNotice draws.
    a = notice_art()
    cells = cut(a, 1, SKY)
    cols = len(a[0]) // 8
    table = bytearray()
    for ty in range(len(NOTICE)):
        row = [SKY] * 32
        for tx in range(cols):
            row[(32 - cols) // 2 + tx] = cells[(ty, tx)]
        table += bytes(row)
    rom[_off(NOTICE_BANK, NOTICE_ADDR):_off(NOTICE_BANK, NOTICE_ADDR) + len(table)] = table

    # New rows 4-14.
    lo, hi = PANEL
    new = []
    for r in range(11):
        row = [SKY] * 32
        nrow = NT_ROW0 + r
        for c in range(lo, hi + 1):
            row[c] = WHITE
        if r < 9:                                           # rows 4-12: the logo
            for c in range(5, 27):
                row[c - SHIFT] = old[r][c]
            if ART_ROW <= nrow < ART_ROW + ART_H // 8:
                for tx in range(ART_W // 8):
                    row[ART_COL + tx] = glyph[(nrow - ART_ROW, tx)]
        elif r == 9:                                        # row 13: the bar
            for c in range(lo + 1, hi):
                row[c] = BAR
            row[lo + 1] = BAR_L
            row[hi - 1] = BAR_R
            for i, (k, _) in enumerate(KANA):
                row[lo + 5 + 6 * i] = k
        else:                                               # row 14: its foot and the panel's bottom
            for c in range(lo + 1, hi):
                row[c] = BAR_FOOT
            row[lo] = row[hi] = BOTTOM
            for i, (_, k) in enumerate(KANA):
                row[lo + 5 + 6 * i] = k
        new.append(row)
    for r, row in enumerate(new):
        rom[nt_off + r * 32:nt_off + r * 32 + 32] = bytes(row)

    # Attributes: palette 0 inside the panel, 2 on its bottom row (as before),
    # 1 (the sky) elsewhere. The panel's outer columns 1 and 30 are white, which
    # looks the same in every palette, so they can share cells with the sky.
    at = _off(TITLE_BANK, ATTR_ADDR)
    attr = bytearray(rom[at:at + 64])

    def setpal(trow, tcol, pal):
        i = (trow // 4) * 8 + tcol // 4
        sh = ((trow % 4) // 2) * 4 + ((tcol % 4) // 2) * 2
        attr[i] = (attr[i] & ~(3 << sh) & 0xFF) | (pal << sh)

    for trow in range(4, 16, 2):
        for tcol in range(0, 32, 2):
            inside = lo + 1 <= tcol <= hi - 1
            if trow == 14:
                pal = 2 if inside else 1
            else:
                pal = 0 if inside else 1
            setpal(trow, tcol, pal)
    rom[at:at + 64] = attr

    # Sprites 0 and 1 sat on the old margins (columns 4 and 27). Put them on the
    # new ones, where they are hidden behind white again.
    oam = _off(TITLE_BANK, OAM_ADDR)
    rom[oam + 3] = lo * 8
    rom[oam + 7] = hi * 8

    # Point the title at the copies.
    for addr, p in zip(CHR_IMM, new_pages):
        rom[_off(TITLE_BANK, addr)] = p
    return len(slots)


# ---- Preview --------------------------------------------------------------------

NES_RGB = {
    0x0F: (0, 0, 0), 0x00: (102, 102, 102), 0x10: (173, 173, 173), 0x30: (255, 254, 255),
    0x21: (100, 176, 255), 0x31: (192, 223, 255), 0x2C: (56, 204, 108), 0x37: (255, 213, 140),
}


def preview(rom, chr_base, path):
    """Draw rows 0-16 of the title nametable from rom to a PNG."""
    from PIL import Image
    nt_off = _off(TITLE_BANK, NT_ADDR)
    at = _off(TITLE_BANK, ATTR_ADDR)
    pages = [rom[_off(TITLE_BANK, a)] for a in CHR_IMM]
    pal_off = _off(TITLE_BANK, 0x8222)
    pal = rom[pal_off:pal_off + 16]
    im = Image.new("RGB", (256, 17 * 8))
    for trow in range(17):
        for tcol in range(32):
            t = rom[nt_off + (trow - NT_ROW0) * 32 + tcol] if NT_ROW0 <= trow < 30 else SKY
            if NOTICE_ROW <= trow < NOTICE_ROW + len(NOTICE):
                t = rom[_off(NOTICE_BANK, NOTICE_ADDR) + (trow - NOTICE_ROW) * 32 + tcol]
            i = (trow // 4) * 8 + tcol // 4
            sh = ((trow % 4) // 2) * 4 + ((tcol % 4) // 2) * 2
            p = (rom[at + i] >> sh) & 3
            o = chr_base + pages[t >> 6] * 1024 + (t & 0x3F) * 16
            px = decode_tile(rom[o:o + 16])
            for y in range(8):
                for x in range(8):
                    v = px[y][x]
                    col = pal[0] if v == 0 else pal[p * 4 + v]
                    im.putpixel((tcol * 8 + x, trow * 8 + y), NES_RGB.get(col, (255, 0, 255)))
    im.resize((im.width * 3, im.height * 3), Image.NEAREST).save(path)


if __name__ == "__main__":
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import build
    rom = build.expand(build.load_rom())
    chr_base = 16 + build.NEW_PRG_BANKS * BANK
    preview(rom, chr_base, os.path.join(build.OUT, "title_before.png"))
    n = patch(rom, chr_base, (0x80, 0x81, 0x82, 0x83), [])
    preview(rom, chr_base, os.path.join(build.OUT, "title.png"))
    print("title: %d new tiles; wrote out/title.png and out/title_before.png" % n)
    for row in art():
        print("".join("#x+ "[v] for v in row))
