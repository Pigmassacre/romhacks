import sys
from PIL import Image, ImageDraw
from nes import load_rom, tile_pixels, draw_tile
rom = sys.argv[1]
pages = [int(p, 16) for p in sys.argv[2].split(',')]
out = sys.argv[3]
pal = [0x0f, 0x0b, 0x2a, 0x30]
_, chr_ = load_rom(rom)
S = 3
img = Image.new('RGB', (len(pages) * (16 * 9 * S + 10), 4 * 18 * S + 20), (90, 90, 140))
d = ImageDraw.Draw(img)
for pi, p in enumerate(pages):
    ox = pi * (16 * 9 * S + 10)
    d.text((ox, 0), 'page %02x' % p, fill=(255, 255, 0))
    for t in range(0, 64, 2):
        col, row = (t // 2) % 16, (t // 2) // 16
        for k in range(2):
            draw_tile(img, tile_pixels(chr_, p * 1024 + (t + k) * 16), ox + col * 9 * S, 12 + row * 36 * S // 2 * 2 + k * 8 * S, pal, scale=S)
img.save(out)
