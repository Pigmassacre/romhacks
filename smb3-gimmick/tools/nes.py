NES_RGB = [
    (84, 84, 84), (0, 30, 116), (8, 16, 144), (48, 0, 136), (68, 0, 100), (92, 0, 48), (84, 4, 0), (60, 24, 0),
    (32, 42, 0), (8, 58, 0), (0, 64, 0), (0, 60, 0), (0, 50, 60), (0, 0, 0), (0, 0, 0), (0, 0, 0),
    (152, 150, 152), (8, 76, 196), (48, 50, 236), (92, 30, 228), (136, 20, 176), (160, 20, 100), (152, 34, 32), (120, 60, 0),
    (84, 90, 0), (40, 114, 0), (8, 124, 0), (0, 118, 40), (0, 102, 120), (0, 0, 0), (0, 0, 0), (0, 0, 0),
    (236, 238, 236), (76, 154, 236), (120, 124, 236), (176, 98, 236), (228, 84, 236), (236, 88, 180), (236, 106, 100), (212, 136, 32),
    (160, 170, 0), (116, 196, 0), (76, 208, 32), (56, 204, 108), (56, 180, 204), (60, 60, 60), (0, 0, 0), (0, 0, 0),
    (236, 238, 236), (168, 204, 236), (188, 188, 236), (212, 178, 236), (236, 174, 236), (236, 174, 212), (236, 180, 176), (228, 196, 144),
    (204, 210, 120), (180, 222, 120), (168, 226, 144), (152, 226, 180), (160, 214, 228), (160, 162, 160), (0, 0, 0), (0, 0, 0),
]


def load_rom(path):
    data = open(path, 'rb').read()
    prg_banks = data[4]
    chr_banks = data[5]
    prg = data[16:16 + prg_banks * 0x4000]
    chr_ = data[16 + prg_banks * 0x4000:16 + prg_banks * 0x4000 + chr_banks * 0x2000]
    return prg, chr_


def tile_pixels(chr_, offset):
    rows = []
    for y in range(8):
        lo = chr_[offset + y]
        hi = chr_[offset + y + 8]
        rows.append([((lo >> (7 - x)) & 1) | (((hi >> (7 - x)) & 1) << 1) for x in range(8)])
    return rows


def encode_tile(pix):
    out = bytearray(16)
    for y in range(8):
        lo = hi = 0
        for x in range(8):
            v = pix[y][x]
            lo |= (v & 1) << (7 - x)
            hi |= ((v >> 1) & 1) << (7 - x)
        out[y] = lo
        out[y + 8] = hi
    return bytes(out)


def draw_tile(img, pix, x0, y0, pal, hflip=False, vflip=False, scale=1):
    for y in range(8):
        for x in range(8):
            sx = 7 - x if hflip else x
            sy = 7 - y if vflip else y
            v = pix[sy][sx]
            if v == 0:
                continue
            c = NES_RGB[pal[v] & 0x3F]
            for dy in range(scale):
                for dx in range(scale):
                    px, py = x0 + x * scale + dx, y0 + y * scale + dy
                    if 0 <= px < img.width and 0 <= py < img.height:
                        img.putpixel((px, py), c)
