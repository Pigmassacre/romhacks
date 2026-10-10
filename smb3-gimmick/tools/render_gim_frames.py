import sys
from PIL import Image, ImageDraw
from nes import load_rom, tile_pixels, draw_tile

prg, chr_ = load_rom(sys.argv[1] if len(sys.argv) > 1 else 'Gimmick! (Japan).nes')
BANK = 15 * 0x4000
PALS = [[0x0f, 0x0b, 0x2a, 0x30], [0x0f, 0x07, 0x30, 0x27], [0x0f, 0x0f, 0x00, 0x30], [0x0f, 0x05, 0x25, 0x30]]


def rd(a):
    return prg[BANK + a - 0x8000]


def frame_sprites(ptr_table, i):
    p = rd(ptr_table + 2 * i) | rd(ptr_table + 2 * i + 1) << 8
    out = []
    while rd(p) != 0:
        dy, t, a, dx = rd(p), rd(p + 1), rd(p + 2), rd(p + 3)
        out.append((dy - 256 if dy > 127 else dy, t, a, dx - 256 if dx > 127 else dx))
        p += 4
    return out


def main():
    n = 22
    S = 4
    cell = 40
    img = Image.new('RGB', (n * cell * S // 2 + 8, 2 * cell * S + 8), (90, 90, 140))
    d = ImageDraw.Draw(img)
    for i in range(n):
        page = rd(0x85ce + i)
        spr = frame_sprites(0x843d, i)
        print(i, 'page %02x' % page, spr)
        cx = (i % (n // 2)) * cell * S + 20 * S
        cy = (i // (n // 2)) * cell * S + 32 * S
        d.text((cx - 18 * S, cy - 30 * S), str(i), fill=(255, 255, 0))
        for dy, t, a, dx in spr:
            assert t < 0x40 and t % 2 == 0
            top = page * 1024 + t * 16
            vf = bool(a & 0x80)
            parts = [top + 16, top] if vf else [top, top + 16]
            for k, off in enumerate(parts):
                draw_tile(img, tile_pixels(chr_, off), cx + dx * S, cy + (dy + 8 * k) * S, PALS[a & 3], bool(a & 0x40), vf, S)
        d.line([(cx - 2, cy), (cx + 2, cy)], fill=(255, 0, 0))
    img.save('out/gim_frames.png')


main()
