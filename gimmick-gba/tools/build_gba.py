#!/usr/bin/env python3
"""Build the game for the GBA, from your own copy of the ROM.

    python3 tools/build_gba.py           # out/gimmick.gba, plays from the buttons
    python3 tools/build_gba.py --replay [trace-dir]  # out/gimmick_replay.gba

The replay build plays a recording (out/trace unless named) and compares RAM with
the PC build's RAM in out/host_ram.bin, which tools/compare.py has checked against
the NES. So run tools/check_host.sh on that recording first. Needs devkitARM.

--timing also leaves out everything that is only there for the check, so the timing it
reports is the real build's. It has no exact timing, so its RAM can drift from the
recording on a heavy frame, and it does not check RAM.
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


def sync_table(path, trace):
    """Where the recording took each NMI, for the replay to take it there too."""
    ram = open(os.path.join(trace, "ram.bin"), "rb")
    with open(path, "wb") as f:
        for n, line in enumerate(open(os.path.join(trace, "cpu.txt"))):
            _, _, a, x, y, s, _ = map(int, line.split())
            ram.seek(n * SIZE + 0x100 + s + 2)
            pc = ram.read(2)
            ram.seek(n * SIZE)
            scratch = 0
            for v in ram.read(0x1B):
                scratch = (scratch * 3 + v) & 0xFFFFFFFF
            f.write(pc + bytes([a, x, y, s]) + struct.pack("<H", scratch & 0xFFFF))


def expected_table(path, trace):
    host = open(os.path.join(OUT, "host_ram.bin"), "rb")
    sps = [int(l.split()[5]) for l in open(os.path.join(trace, "cpu.txt"))]
    frames = min(os.path.getsize(host.name) // SIZE, len(sps))
    with open(path, "wb") as f:
        for n in range(frames):
            host.seek(n * SIZE)
            r = host.read(0x800)
            f.write(struct.pack("<I", fnv(r[:0x100] + r[0x200:])))


def main():
    replay = "--replay" in sys.argv
    subprocess.run([sys.executable, os.path.join(REPO, "tools", "recomp.py")], check=True, stdout=subprocess.DEVNULL)
    rom = open(ROM, "rb").read()[16:]
    chr4 = os.path.join(GEN, "chr4.bin")
    open(chr4, "wb").write(chr_to_4bpp(rom[0x40000:0x60000]))
    prg_bin, chr_bin = os.path.join(GEN, "prg.bin"), os.path.join(GEN, "chr.bin")
    open(prg_bin, "wb").write(rom[:0x40000])
    open(chr_bin, "wb").write(rom[0x40000:0x60000])
    data = ['.section .rodata', '.global rom_prg, rom_chr, chr4_data', '.balign 4',
            'rom_prg: .incbin "%s"' % prg_bin, 'rom_chr: .incbin "%s"' % chr_bin,
            '.balign 4', 'chr4_data: .incbin "%s"' % chr4]
    flags = ["-mcpu=arm7tdmi", "-mthumb", "-mthumb-interwork", "-O2", "-w", "-ffixed-r7", "-ffixed-r6", "-fomit-frame-pointer", "-specs=gba.specs",
             "-I" + os.path.join(REPO, "runtime")]
    name = "gimmick"
    if replay:
        name = "gimmick_replay"
        after = [a for a in sys.argv[sys.argv.index("--replay") + 1:] if a != "--timing"]
        trace = os.path.abspath(after[0]) if after else os.path.join(OUT, "trace")
        table = os.path.join(GEN, "expected.bin")
        expected_table(table, trace)
        pads = os.path.join(trace, "padreads.bin")
        sync = os.path.join(GEN, "sync.bin")
        sync_table(sync, trace)
        pokes = os.path.join(GEN, "pokes.bin")
        with open(pokes, "wb") as f:
            for line in open(os.path.join(trace, "pokes.txt")):
                nmi, a, v = map(int, line.split())
                f.write(struct.pack("<IHH", nmi, a, v))
        data += ['.global pad_stream, pad_stream_end, expected, expected_end, pokes, pokes_end, power_on_ram, nmi_sync_table, nmi_sync_end',
                 'pad_stream: .incbin "%s"' % pads, 'pad_stream_end:', '.balign 4',
                 'expected: .incbin "%s"' % table, 'expected_end:',
                 'pokes: .incbin "%s"' % pokes, 'pokes_end:',
                 '.balign 4', 'nmi_sync_table: .incbin "%s"' % sync, 'nmi_sync_end:',
                 'power_on_ram: .incbin "%s"' % os.path.join(trace, "poweron.bin")]
        flags.append("-DREPLAY")
        if "--timing" in sys.argv:
            flags.append("-DTIMING_ONLY")
    data_s = os.path.join(GEN, "data.s")
    open(data_s, "w").write("\n".join(data) + "\n")
    sources = [os.path.join(REPO, "runtime", s) for s in ("gba.c", "core.c", "apu.c", "video.c")]
    sources += sorted(os.path.join(GEN, f) for f in os.listdir(GEN) if f.endswith(".c"))
    elf = os.path.join(OUT, name + ".elf")
    gba = os.path.join(OUT, name + ".gba")
    env = dict(os.environ, PATH=BIN + os.pathsep + os.environ["PATH"])
    subprocess.run([GCC] + flags + sources + [data_s, "-o", elf], check=True, env=env)
    subprocess.run([os.path.join(BIN, "arm-none-eabi-objcopy"), "-O", "binary", elf, gba], check=True)
    subprocess.run([GBAFIX, gba, "-tGIMMICK"], check=True, stdout=subprocess.DEVNULL)
    print("%s: %d KB" % (gba, os.path.getsize(gba) // 1024))
    nm = subprocess.run([os.path.join(BIN, "arm-none-eabi-nm"), elf], capture_output=True, text=True).stdout
    for line in nm.splitlines():
        if line.endswith(" __bss_end__"):
            free = 0x03007F00 - int(line.split()[0], 16)
            print("fast RAM left above the stack's top: %d bytes" % free)


if __name__ == "__main__":
    main()
