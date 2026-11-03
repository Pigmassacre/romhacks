#!/usr/bin/env python3
"""Build the game for the GBA, from your own copy of the ROM.

    python3 tools/build_gba.py           # out/gimmick.gba, plays from the buttons
    python3 tools/build_gba.py --replay [trace-dir]  # out/gimmick_replay.gba
    python3 tools/build_gba.py --replay [trace-dir] --timing [--no-slowdown]

The replay build plays a recording (out/trace unless named) and compares RAM with
the PC build's RAM in out/host_ram.bin, which tools/compare.py has checked against
the NES. So run tools/check_host.sh on that recording first. Needs devkitARM.

--timing also leaves out everything that is only there for the check, so the timing it
reports is the real build's. It has no exact timing, so its RAM can drift from the
recording on a heavy frame, and it does not check RAM. It keeps the NES's slowdown, which
the real build does not have, so that the recording's buttons play the same game;
--no-slowdown leaves it out, for a recording where nothing is pressed (--crowd).
"""
import os
import re
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


# What the stack needs at least, in fast RAM. A replay of the boss fight reached about
# 800 bytes deep; past the end, the stack overwrites the program's data and the game
# breaks. How much fast RAM the hot code takes is only estimated when it is picked, so
# the build shrinks it until this much is left.
STACK_ROOM = 1536


def main():
    replay = "--replay" in sys.argv
    hot = 30000 if replay and "--timing" not in sys.argv else int(os.environ.get("HOT_BYTES", 44000))
    while True:
        free = build(replay, hot)
        if free >= STACK_ROOM:
            break
        # About 2.5 bytes of the estimate make one real byte, so this leaves some over.
        hot -= (STACK_ROOM - free) * 3 + 200
        print("too little left for the stack: hot code down to %d (estimated) bytes" % hot)


def build(replay, hot):
    env = dict(os.environ, HOT_BYTES=str(hot))
    subprocess.run([sys.executable, os.path.join(REPO, "tools", "recomp.py")], check=True, stdout=subprocess.DEVNULL, env=env)
    rom = open(ROM, "rb").read()[16:]
    chr4, par = os.path.join(GEN, "chr4.bin"), os.path.join(GEN, "parallax.bin")  # from recomp.py
    prg_bin, chr_bin = os.path.join(GEN, "prg.bin"), os.path.join(GEN, "chr.bin")
    # recomp.py has written prg.bin: the game's, with Gimmick! 1.5's bank after it.
    open(chr_bin, "wb").write(rom[0x40000:0x60000])
    data = ['.section .rodata', '.global rom_prg, rom_chr, chr4_data, parallax_data', '.balign 4',
            'rom_prg: .incbin "%s"' % prg_bin, 'rom_chr: .incbin "%s"' % chr_bin,
            '.balign 4', 'chr4_data: .incbin "%s"' % chr4, '.balign 4', 'parallax_data: .incbin "%s"' % par]
    flags = ["-mcpu=arm7tdmi", "-mthumb", "-mthumb-interwork", "-O2", "-w", "-ffixed-r7", "-ffixed-r6", "-fomit-frame-pointer", "-specs=gba.specs",
             "-I" + os.path.join(REPO, "runtime")]
    name = "gimmick"
    if replay:
        name = "gimmick_replay"
        after = [a for a in sys.argv[sys.argv.index("--replay") + 1:] if not a.startswith("--")]
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
        # A recording of the NES game with all of Gimmick! 1.5 on is replayed with all
        # its options on.
        # REPLAY_OPTIONS in the environment picks other options, to time them.
        if os.environ.get("REPLAY_OPTIONS"):
            flags.append("-DREPLAY_OPTIONS=" + os.environ["REPLAY_OPTIONS"])
        elif os.path.basename(trace.rstrip("/")) == "ref15":
            flags.append("-DREPLAY_OPTIONS=OPT_ALL")
        if "--timing" in sys.argv:
            flags.append("-DTIMING_ONLY")
            # The build you play has no slowdown, but a recording's buttons only replay
            # the same game with the NES's frames: tests/s_crowd.lua presses nothing,
            # for timing without it.
            if "--no-slowdown" not in sys.argv:
                flags.append("-DKEEP_SLOWDOWN")
    data_s = os.path.join(GEN, "data.s")
    open(data_s, "w").write("\n".join(data) + "\n")
    sources = [os.path.join(REPO, "runtime", s) for s in ("gba.c", "core.c", "apu.c", "video.c")]
    sources += sorted(os.path.join(GEN, f) for f in os.listdir(GEN) if f.endswith(".c"))
    elf = os.path.join(OUT, name + ".elf")
    gba = os.path.join(OUT, name + ".gba")
    env = dict(os.environ, PATH=BIN + os.pathsep + os.environ["PATH"])
    link = subprocess.run([GCC] + flags + sources + [data_s, "-o", elf], env=env, capture_output=True, text=True)
    # Too much for fast RAM at all: as if the stack had that much less than nothing.
    over = [int(m, 16) for m in re.findall(r"address (0x[0-9a-f]+) of \S+ section \S+ is not within region `iwram'", link.stderr)]
    if over:
        print("fast RAM overflowed by %d bytes" % (max(over) - 0x03008000))
        return 0x03007F00 - max(over)
    if link.returncode:
        sys.exit(link.stdout + link.stderr)
    subprocess.run([os.path.join(BIN, "arm-none-eabi-objcopy"), "-O", "binary", elf, gba], check=True)
    subprocess.run([GBAFIX, gba, "-tGIMMICK ADV"], check=True, stdout=subprocess.DEVNULL)
    print("%s: %d KB" % (gba, os.path.getsize(gba) // 1024))
    nm = subprocess.run([os.path.join(BIN, "arm-none-eabi-nm"), elf], capture_output=True, text=True).stdout
    # Fast RAM's data ends at __iheap_start: the initialised data goes after the zeroed,
    # so __bss_end__ is not the end. The stack grows down to it from 0x03007F00.
    for line in nm.splitlines():
        if line.endswith(" __iheap_start"):
            free = 0x03007F00 - int(line.split()[0], 16)
            print("fast RAM left for the stack: %d bytes" % free)
            return free


if __name__ == "__main__":
    main()
