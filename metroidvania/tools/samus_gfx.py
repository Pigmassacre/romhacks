#!/usr/bin/env python3
"""Convert Samus's graphics and animation frames from Metroid for Castlevania.

Metroid draws sprites 8x8; Castlevania draws them 8x16, two tiles stacked
(an even tile on top of the next one). Each of Samus's frames is decoded the
way Metroid's ObjDrawFrame lays it out, then sprites in the same column, 8
pixels apart and with the same palette, are paired into one 8x16 sprite, with
their flips baked into the tiles. A sprite with no partner gets a blank half.
Every distinct pair (mirror images count as one) gets two tiles:

- first in Castlevania's sprite pattern table, in the tiles only Simon and
  his whip used. Those come from bank 1 of the ROM ($9008 holds tile 0), so
  the build writes Samus's pairs straight over Simon's there.
- the rest in the background pattern table, over the status bar's font
  ($1D00-$1FDF). Sprites reach them with odd tile numbers. The font is
  loaded with each stage, so the hack copies these pairs in after every
  load (src/chr.asm), and puts the font back for the Game Over screen.

Writes, into out/gen/:
  samus_chr.asm     the pairs for the font area, and the HUD's fixed pairs
  samus_frames.asm  frame data for src/draw.asm, Metroid's animation table,
                    and constants for both
and returns the sprite table pairs for the build to write into bank 1.
"""
import os

BANK = 0x4000
ANIM_TBL = 0x8572           # ObjectAnimIndexTbl in Metroid bank 1
ANIM_LEN = 153
FRAME_PTRS = 0x860B         # ObjFramePtrTable
PLACE_PTRS = 0x86DF         # ObjPlacePtrTable
SAMUS_GFX = (6, 0x8000, 0x09A0)     # GFXInfo entry 0: tiles $00-$99
HUD_FONT = (6, 0xB4C0, 0x00A0)      # GFXInfo entry $18: digits, tiles $A0-$A9

# Offsets into ObjectAnimIndexTbl of the animations the hack uses (names from
# the m1disasm disassembly).
ANIMS = {
    "SamusRun": 0x00, "SamusFront": 0x04, "SamusUnroll": 0x06, "SamusStand": 0x07,
    "SamusStandFire": 0x09, "SamusJumpTransition": 0x0B, "SamusJump": 0x0C,
    "SamusSalto": 0x0E, "SamusRunJump": 0x13, "SamusRoll": 0x16, "RegularBullet": 0x1B,
    "BulletHit": 0x1D, "SamusJumpFire": 0x20, "SamusRunFire": 0x22, "SamusPntUpFire": 0x26,
    "SamusPntUp": 0x27, "SamusExplode": 0x32, "SamusJumpPntUpFire": 0x34,
    "SamusJumpPntUp": 0x35, "SamusRunPntUp": 0x37, "SamusRunPntUpFire1": 0x3B,
    "SamusRunPntUpFire2": 0x3D, "SamusRunPntUpFire3": 0x3F, "MissileLeft": 0x8B,
    "MissileRight": 0x8D, "MissileUp": 0x8F, "MissileExplode": 0x91,
}
FRAME_NAMES = {
    0x03: "SamusRun0", 0x04: "SamusRun1", 0x05: "SamusRun2", 0x07: "SamusFront",
    0x08: "SamusStand", 0x0C: "SamusRunFire0", 0x0D: "SamusRunFire1", 0x0E: "SamusRunFire2",
    0x10: "SamusJump", 0x12: "SamusJumpFire", 0x17: "SamusSalto0", 0x18: "SamusSalto1",
    0x19: "SamusSalto2", 0x1A: "SamusSalto3", 0x1B: "SamusRoll3", 0x1C: "SamusRoll2",
    0x1D: "SamusRoll1", 0x1E: "SamusRoll0", 0x22: "SamusStandFire", 0x25: "MissileRight",
    0x26: "MissileLeft", 0x27: "MissileUp", 0x28: "RegularBullet", 0x2A: "BulletHit",
    0x2B: "SamusPntUp", 0x30: "SamusPntUpFire", 0x35: "SamusExplode",
    0x38: "SamusJumpPntUp", 0x39: "SamusJumpPntUpFire", 0x40: "SamusRunPntUp0",
    0x41: "SamusRunPntUp1", 0x42: "SamusRunPntUp2", 0x46: "SamusRunPntUpFire0",
    0x47: "SamusRunPntUpFire1", 0x48: "SamusRunPntUpFire2", 0x67: "MissileExplode0",
    0x68: "MissileExplode1", 0x69: "MissileExplode2",
}

# Sprite tiles that only Simon and the whip use (even = top of a pair). Pair
# $00 is blank, and stays blank: Castlevania leaves some of its own sprites
# (Dracula's head, 1-8) on it to hide them.
SPRITE_PAIRS = (list(range(0x02, 0x40, 2)) + list(range(0x46, 0x50, 2)) +
                list(range(0x52, 0x60, 2)) + list(range(0x6A, 0x70, 2)))
# The status bar font, $1D00-$1FDF, as sprite tile numbers (odd: $1000 table).
# $FE-$FF stay: they are sprite 0's.
FONT_PAIRS = list(range(0xD1, 0xFE, 2))
# HUD sprites (see src/hud.asm): TI over E, ME over N and the missile's two
# halves are fixed; the six digit columns are composed at run time.
HUD_PAIRS = 10

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def s8(v):
    return v - 256 if v >= 128 else v


class Metroid:
    def __init__(self, prg):
        self.prg = prg

    def rd(self, bank, addr, n=1):
        off = bank * BANK + (addr - 0x8000)
        return self.prg[off:off + n]

    def byte(self, addr):
        return self.rd(1, addr)[0]

    def word(self, addr):
        b = self.rd(1, addr, 2)
        return b[0] | b[1] << 8

    def tile(self, t):
        """16 bytes of Metroid sprite tile t, as loaded in the pattern table."""
        if 0xA0 <= t < 0xAA:
            bank, src, size = HUD_FONT
            return self.rd(bank, src + (t - 0xA0) * 16, 16)
        bank, src, size = SAMUS_GFX
        if t * 16 >= size:
            raise ValueError("tile %02X is not in Samus's graphics" % t)
        return self.rd(bank, src + t * 16, 16)


def decode_frame(met, fid):
    """Sprites of frame fid facing right: [(dy, dx, tile, attr)] around the object.

    dy is already the OAM y offset (Metroid stores y - 1 in sprite RAM).
    Returns None for frames that use the exploding placement (drawn by code).
    """
    ptr = met.word(FRAME_PTRS + 2 * fid)
    b0 = met.byte(ptr)
    place = met.word(PLACE_PTRS + 2 * (b0 & 0x0F))
    flip = b0                                   # Temp04: position flips
    cntrl = ((b0 >> 4) & 3) | (b0 & 0xC0) | 0x20  # Temp05: attributes
    i, pi = 3, 0
    oy = ox = 0
    out = []
    while True:
        c = met.byte(ptr + i)
        if c < 0xFC:
            py, px = met.byte(place + pi), met.byte(place + pi + 1)
            if py & 0xF0 == 0x80:
                return None
            y = (-s8(py) - 8) if flip & 0x80 else s8(py)
            x = (-s8(px) - 8) if flip & 0x40 else s8(px)
            out.append((y + oy - 1, x + ox, c, cntrl))
            pi += 2
            i += 1
        elif c == 0xFC:
            oy += s8(met.byte(ptr + i + 1))
            ox += s8(met.byte(ptr + i + 2))
            i += 3
        elif c == 0xFD:
            cntrl = met.byte(ptr + i + 1)
            i += 2
        elif c == 0xFE:
            pi += 2
            i += 1
        else:
            return out


def flip_tile(data, h, v):
    lo, hi = list(data[:8]), list(data[8:])
    if h:
        rev = lambda b: int("{:08b}".format(b)[::-1], 2)
        lo, hi = [rev(b) for b in lo], [rev(b) for b in hi]
    if v:
        lo, hi = lo[::-1], hi[::-1]
    return bytes(lo + hi)


BLANK = bytes(16)


def pair_sprites(sprites, tile):
    """Pair 8x8 sprites into 8x16 ones: [(dy, dx, top, bottom, palette)].

    tile(t, attr) gives the 16 bytes of sprite t as shown with attr's flips.
    top/bottom are those shown images (BLANK for an empty half). Sprites pair
    up when they are in the same column, 8 pixels apart, with the same
    palette; their flips are baked into the images. The priority bit is
    dropped, because Castlevania's backgrounds are opaque where Metroid's
    are not.
    """
    left = sorted(sprites, key=lambda s: (s[1], s[0]))
    used = [False] * len(left)
    out = []
    for i, (y, x, t, a) in enumerate(left):
        if used[i]:
            continue
        used[i] = True
        partner = None
        for j in range(i + 1, len(left)):
            y2, x2, t2, a2 = left[j]
            if not used[j] and x2 == x and y2 == y + 8 and (a2 & 3) == (a & 3):
                partner = j
                break
        bottom = BLANK
        if partner is not None:
            used[partner] = True
            bottom = tile(left[partner][2], left[partner][3])
        out.append((y, x, tile(t, a), bottom, a & 3))
    return out


def canonical(top, bottom):
    """The stored form of a shown pair, and the flips that show it: (data, attr).

    Of the four flipped versions, the smallest is stored, so mirrored copies
    share tiles. With vertical flip the hardware shows the stored bottom tile,
    flipped, on top, hence the swap.
    """
    best = None
    for h in (0, 1):
        for v in (0, 1):
            t, b = flip_tile(top, h, v), flip_tile(bottom, h, v)
            if v:
                t, b = b, t
            cand = (t + b, h * 0x40 | v * 0x80)
            if best is None or cand[0] < best[0]:
                best = cand
    return best


# Metroid's HUD colours (its sprite palette 1) in the palette the HUD uses
# here: palette 2, which has Metroid's colours above the status bar split.
HUD_COLOURS = {0: 0, 1: 1, 2: 2, 3: 3}


def hud_tile(met, t):
    d = met.tile(t)
    lo, hi = bytearray(8), bytearray(8)
    for y in range(8):
        for x in range(8):
            c = ((d[y] >> (7 - x)) & 1) | (((d[8 + y] >> (7 - x)) & 1) << 1)
            c = HUD_COLOURS[c]
            lo[y] |= (c & 1) << (7 - x)
            hi[y] |= (c >> 1) << (7 - x)
    return bytes(lo + hi)


def hexrows(f, data):
    for k in range(0, len(data), 16):
        f.write("  .db " + ",".join("$%02X" % b for b in data[k:k + 16]) + "\n")


def build(met_prg, outdir):
    met = Metroid(met_prg)
    table = met.rd(1, ANIM_TBL, ANIM_LEN)
    shown = lambda t, a: flip_tile(met.tile(t), a & 0x40, a & 0x80)

    # Frames the chosen animations use.
    used = set()
    for name, o in ANIMS.items():
        while table[o] != 0xFF:
            if table[o] != 0xF7:
                used.add(table[o])
            o += 1
    used = sorted(used)

    slots = SPRITE_PAIRS[HUD_PAIRS:] + FONT_PAIRS
    pairs = {}          # stored 32 bytes -> CV tile number

    framedata = {}
    for fid in used:
        spr = decode_frame(met, fid)
        if spr is None:
            framedata[fid] = None
            continue
        out = []
        for y, x, top, bottom, pal in pair_sprites(spr, shown):
            data, flips = canonical(top, bottom)
            if data not in pairs:
                if len(pairs) == len(slots):
                    raise ValueError("Samus needs more than %d tile pairs" % len(slots))
                pairs[data] = slots[len(pairs)]
            out.append((y, x, pairs[data], flips | pal))
        framedata[fid] = out

    # Samus's explosion (frame $35, drawn by code): six single tiles
    explode = []
    for t in (0x0B, 0x0C, 0x1B, 0x1C, 0x2B, 0x2C):
        data = met.tile(t) + BLANK
        if data not in pairs:
            pairs[data] = slots[len(pairs)]
        explode.append(pairs[data])

    sprite_chr = [(t, d) for d, t in pairs.items() if t % 2 == 0]
    for k, (top, bottom) in enumerate(((0x58, 0x76), (0x59, 0x7F))):
        sprite_chr.append((SPRITE_PAIRS[k], hud_tile(met, top) + hud_tile(met, bottom)))
    for k, t in enumerate((0x5E, 0x5F)):
        sprite_chr.append((SPRITE_PAIRS[2 + k], met.tile(t) + BLANK))
    font_chr = sorted((t, d) for d, t in pairs.items() if t % 2 == 1)

    with open(os.path.join(outdir, "samus_chr.asm"), "w") as f:
        f.write("; Generated by tools/samus_gfx.py from Metroid's graphics. Do not edit.\n\n")
        f.write("; Samus's tile pairs in the background table, over the status bar font:\n")
        f.write("; from $%04X on, %d pairs back to back.\n" % (0x1000 + (font_chr[0][0] & 0xFE) * 16 if font_chr else 0x1D00, len(font_chr)))
        f.write("FontChrAddr = $%04X\nFontChrSize = %d\nFontChr:\n" %
                (0x1000 + (FONT_PAIRS[0] & 0xFE) * 16, 32 * len(font_chr)))
        for k, (t, d) in enumerate(font_chr):
            assert t == FONT_PAIRS[k]
            hexrows(f, d)
        f.write("\n; HUD glyphs for the digit columns, 16 bytes each: 0-9, \"..\", blank, a\n; full energy tank.\n")
        f.write("GlyphTable:\n")
        glyphs = [hud_tile(met, 0xA0 + d) for d in range(10)] + [hud_tile(met, 0x3A), BLANK, hud_tile(met, 0x6F)]
        for g in glyphs:
            # the update buffer reads $FF as the end of a write, unless a
            # byte of 3 or more follows it
            assert g[-1] != 0xFF and all(g[k + 1] >= 3 for k in range(15) if g[k] == 0xFF)
            hexrows(f, g)
        for k in range(HUD_PAIRS):
            f.write("HudTile%d = $%02X\n" % (k, SPRITE_PAIRS[k]))
        f.write("ExplodeTiles:\n  .db " + ",".join("$%02X" % t for t in explode) + "\n")

    with open(os.path.join(outdir, "samus_frames.asm"), "w") as f:
        f.write("; Generated by tools/samus_gfx.py from Metroid's frames. Do not edit.\n\n")
        for a, o in ANIMS.items():
            f.write("ObjAnim_%s = $%02X\n" % (a, o))
        f.write("\n")
        for fid in used:
            f.write("ObjFrame_%s = $%02X\n" % (FRAME_NAMES.get(fid, "%02X" % fid), fid))
        f.write("FrameNone = $F7\nFrameEnd = $FF\n")
        f.write("\n; Metroid's ObjectAnimIndexTbl, unchanged: animation offsets index it.\n")
        f.write("ObjectAnimIndexTbl:\n")
        hexrows(f, table)
        top = max(used) + 1
        f.write("\n; Frame pointers by Metroid frame id, facing right and left. 0: no frame.\n")
        for side in ("", "L"):
            for part in ("Lo", "Hi"):
                f.write("Frame%sPtr%s:\n" % (side, part))
                for fid in range(top):
                    lab = "Frame%s%02X" % (side, fid) if framedata.get(fid) else "0"
                    f.write("  .db %s%s\n" % ("<" if part == "Lo" else ">", lab))
        # Castlevania's sprite allocator steps $C4 through sprite RAM,
        # skipping $00-$43 (see src/draw.asm)
        f.write("\n; The next sprite after each sprite RAM offset, as Castlevania steps.\nNextOam:\n")
        nxt = []
        for x in range(256):
            v = (x + 0xC4) & 0xFF
            while v < 0x44:
                v = (v + 0xC4) & 0xFF
            nxt.append(v)
        hexrows(f, bytes(nxt))
        f.write("\nFrameCount = %d\n; Radii (Metroid's frame bytes 1 and 2), read when the frame is shown.\n" % top)
        for part, k in (("Y", 1), ("X", 2)):
            f.write("FrameRad%s:\n" % part)
            for fid in range(top):
                f.write("  .db $%02X\n" % (met.byte(met.word(FRAME_PTRS + 2 * fid) + k) if fid in framedata else 0))
        f.write("\n; Each frame: count, then per sprite dy, tile, attributes, dx. FrameL is\n")
        f.write("; the same frame facing left: mirrored the way Metroid mirrors Samus.\n")
        for fid in used:
            spr = framedata[fid]
            if not spr:
                continue
            for side in ("", "L"):
                f.write("Frame%s%02X:  ; %s\n  .db %d\n" % (side, fid, FRAME_NAMES.get(fid, ""), len(spr)))
                for y, x, t, a in spr:
                    if side:
                        x, a = -x - 8, a ^ 0x40
                    f.write("  .db $%02X,$%02X,$%02X,$%02X\n" % (y & 0xFF, t, a, x & 0xFF))
    build.last = (framedata, pairs)
    return sprite_chr, len(pairs), len(slots)


if __name__ == "__main__":
    met = open(os.path.join(REPO, "Metroid.nes"), "rb").read()[16:]
    os.makedirs(os.path.join(REPO, "out", "gen"), exist_ok=True)
    chr_, n, cap = build(met, os.path.join(REPO, "out", "gen"))
    print("%d of %d tile pairs" % (n, cap))
