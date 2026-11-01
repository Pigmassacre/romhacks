#!/usr/bin/env python3
"""Build the game for the GBA, from your own copy of the ROM.

    python3 tools/build_gba.py           # out/gimmick.gba, plays from the buttons
    python3 tools/build_gba.py --replay  # out/gimmick_replay.gba, checks itself

The replay build plays the recording in out/trace and compares RAM with the PC
build's RAM in out/host_ram.bin (which tools/compare.py has checked against the
NES). Needs devkitARM.
"""
import os
import struct
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out")
GEN = os.path.join(OUT, "gen")
ROM = os.path.join(REPO, "Gimmick! (Japan).nes")
DKP = os.environ.get("DEVKITPRO", "/opt/devkitpro")
BIN = os.path.join(DKP, "devkitARM", "bin")
GCC = os.path.join(BIN, "arm-none-eabi-gcc")
GBAFIX = os.path.join(DKP, "tools", "bin", "gbafix")
SIZE = 0x2800
WAIT_LOOP = (0xF29A, 0xF2A5)


def chr_to_4bpp(chr2):
    """NES tiles are 16 bytes, 2 bits a pixel. GBA tiles are 32, 4 bits a pixel."""
    out = bytearray(len(chr2) * 2)
    for t in range(len(chr2) // 16):
        for y in range(8):
            lo, hi = chr2[t * 16 + y], chr2[t * 16 + 8 + y]
            row = 0
            for x in range(8):
                p = (lo >> (7 - x) & 1) | (hi >> (7 - x) & 1) << 1
                row |= p << (x * 4)
            out[t * 32 + y * 4:t * 32 + y * 4 + 4] = struct.pack("<I", row)
    return bytes(out)


def fnv(b):
    h = 2166136261
    for v in b:
        h = ((h ^ v) * 16777619) & 0xFFFFFFFF
    return h | 1


def expected_table(path):
    host = open(os.path.join(OUT, "host_ram.bin"), "rb").read()
    sps = [int(l.split()[5]) for l in open(os.path.join(OUT, "trace", "cpu.txt"))]
    frames = min(len(host) // SIZE, len(sps))
    with open(path, "wb") as f:
        for n in range(frames):
            r = host[n * SIZE:n * SIZE + 0x800]
            pc = r[0x100 + sps[n] + 2] | r[0x100 + sps[n] + 3] << 8
            idle = WAIT_LOOP[0] <= pc <= WAIT_LOOP[1]
            f.write(struct.pack("<I", fnv(r[:0x100] + r[0x200:]) if idle else 0))


def main():
    replay = "--replay" in sys.argv
    rom = open(ROM, "rb").read()[16:]
    chr4 = os.path.join(GEN, "chr4.bin")
    open(chr4, "wb").write(chr_to_4bpp(rom[0x40000:0x60000]))
    prg_bin, chr_bin = os.path.join(GEN, "prg.bin"), os.path.join(GEN, "chr.bin")
    open(prg_bin, "wb").write(rom[:0x40000])
    open(chr_bin, "wb").write(rom[0x40000:0x60000])
    data = ['.section .rodata', '.global rom_prg, rom_chr, chr4', '.balign 4',
            'rom_prg: .incbin "%s"' % prg_bin, 'rom_chr: .incbin "%s"' % chr_bin,
            '.balign 4', 'chr4: .incbin "%s"' % chr4]
    flags = ["-mcpu=arm7tdmi", "-mthumb", "-mthumb-interwork", "-O2", "-w", "-ffixed-r7", "-fomit-frame-pointer", "-specs=gba.specs",
             "-I" + os.path.join(REPO, "runtime")]
    name = "gimmick"
    if replay:
        name = "gimmick_replay"
        table = os.path.join(GEN, "expected.bin")
        expected_table(table)
        pads = os.path.join(OUT, "trace", "padreads.bin")
        data += ['.global pad_stream, pad_stream_end, expected, expected_end',
                 'pad_stream: .incbin "%s"' % pads, 'pad_stream_end:', '.balign 4',
                 'expected: .incbin "%s"' % table, 'expected_end:']
        flags.append("-DREPLAY")
    data_s = os.path.join(GEN, "data.s")
    open(data_s, "w").write("\n".join(data) + "\n")
    sources = [os.path.join(REPO, "runtime", s) for s in ("gba.c", "core.c")]
    sources += sorted(os.path.join(GEN, f) for f in os.listdir(GEN) if f.endswith(".c"))
    elf = os.path.join(OUT, name + ".elf")
    gba = os.path.join(OUT, name + ".gba")
    env = dict(os.environ, PATH=BIN + os.pathsep + os.environ["PATH"])
    subprocess.run([GCC] + flags + sources + [data_s, "-o", elf], check=True, env=env)
    subprocess.run([os.path.join(BIN, "arm-none-eabi-objcopy"), "-O", "binary", elf, gba], check=True)
    subprocess.run([GBAFIX, gba, "-tGIMMICK"], check=True, stdout=subprocess.DEVNULL)
    print("%s: %d KB" % (gba, os.path.getsize(gba) // 1024))


if __name__ == "__main__":
    main()
