#!/usr/bin/env python3
"""Build Metroidvania from your own copies of Castlevania and Metroid.

    python3 tools/build.py            # writes out/metroidvania.nes and .bps

Steps:

1. Read `Castlevania I.nes` and `Metroid.nes` and check they are the right
   games (the PRG checksum; headers are ignored).
2. Expand Castlevania's PRG from 128 KB to 256 KB (UNROM to UOROM, still
   mapper 2). Original banks keep their numbers ($00-$06); the fixed bank is
   copied to $0F, because the mapper always maps the last bank at $C000.
   Banks $07-$0E are new; the hack lives in bank $08.
3. Convert Samus's graphics and animation frames from Metroid
   (tools/samus_gfx.py), into out/gen/.
4. Assemble src/main.asm with asm6. The source is split into segments by
   `;@ seg <bank> <start> <end>` lines. Each segment is assembled at its CPU
   address and its bytes are written into that 16 KB bank. A segment may be
   shorter than its range, never longer.
5. Write the ROM and a BPS patch. The patch copies everything it can from
   Castlevania, so it holds only the new code and Samus's graphics.
"""
import hashlib
import os
import re
import subprocess
import sys
import zlib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
SRC = os.path.join(REPO, "src")
OUT = os.path.join(REPO, "out")
ROM_IN = os.path.join(REPO, "Castlevania I.nes")
MET_IN = os.path.join(REPO, "Metroid.nes")
ROM_OUT = os.path.join(OUT, "metroidvania.nes")
BPS_OUT = os.path.join(OUT, "metroidvania.bps")
ASM6 = os.path.join(REPO, "tools", "asm6")

# MD5 of the 128 KB PRG, without the header.
CV_MD5 = "728e05f245ab8b7fe61083f6919dc485"       # Castlevania (USA), file CRC32 856114C8
MET_MD5 = "b2d2d9ed68b3e5e0d29053ea525bd37c"      # Metroid (USA), file CRC32 A2C89CB9
BANK = 0x4000
OLD_BANKS = 8
NEW_BANKS = 16
FIXED = NEW_BANKS - 1
SIMON_CHR = 0x9008          # bank 1: sprite tile 0

SEG_RE = re.compile(r"^\s*;@\s*seg\s+\$?([0-9A-Fa-f]+)\s+\$?([0-9A-Fa-f]+)\s+\$?([0-9A-Fa-f]+)\s*(.*)$")


def fail(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


def load(path, md5, name):
    if not os.path.exists(path):
        fail("put your copy of %s at %r" % (name, path))
    data = open(path, "rb").read()
    if data[:4] != b"NES\x1a":
        fail("%s is not an iNES file" % path)
    body = data[16:]
    if hashlib.md5(body).hexdigest() != md5:
        fail("this is not %s: body md5 %s" % (name, hashlib.md5(body).hexdigest()))
    return data


def expand(data):
    prg = data[16:]
    banks = [prg[i * BANK:(i + 1) * BANK] for i in range(OLD_BANKS)]
    new = banks[:OLD_BANKS - 1] + [b"\xff" * BANK] * (NEW_BANKS - OLD_BANKS + 1)
    new[FIXED] = banks[OLD_BANKS - 1]
    header = bytearray(data[:16])
    header[4] = NEW_BANKS
    header[5] = 0
    header[6] = 0x21                # mapper 2, vertical mirroring
    header[7:16] = bytes(9)
    return bytearray(bytes(header) + b"".join(new))


def split_segments(path):
    """Return (prologue_lines, [(bank, start, end, name, lines)])."""
    prologue, segs = [], []
    cur = None
    for line in open(path):
        m = SEG_RE.match(line)
        if m:
            bank, start, end = (int(g, 16) for g in m.groups()[:3])
            cur = (bank, start, end, m.group(4).strip() or "%02X:%04X" % (bank, start), [])
            segs.append(cur)
            continue
        (cur[4] if cur else prologue).append(line)
    return prologue, segs


def assemble(prologue, segs):
    """Assemble all segments in one asm6 run so labels resolve across them.

    The output is the segments' bytes back to back, followed by a table of
    their lengths, which tells us where each one ends.
    """
    gen = os.path.join(OUT, "build.asm")
    with open(gen, "w") as f:
        f.writelines(prologue)
        for i, (bank, start, end, name, lines) in enumerate(segs):
            f.write("\n; ---- segment %s\n.base $%04X\n" % (name, start))
            f.writelines(lines)
            f.write("\n__seg%d_end:\n" % i)
            f.write(".if __seg%d_end > $%04X\n.error \"segment %s is too long\"\n.endif\n" % (i, end, name))
        f.write("\n; ---- segment lengths\n")
        for i, (bank, start, end, name, lines) in enumerate(segs):
            f.write(".dw __seg%d_end - $%04X\n" % (i, start))
    binp = os.path.join(OUT, "build.bin")
    lst = os.path.join(OUT, "build.lst")
    # asm6 reads arguments that start with "/" as options, so pass relative paths.
    rel = [os.path.relpath(p, SRC) for p in (gen, binp, lst)]
    if os.path.exists(binp):
        os.remove(binp)
    if not os.path.exists(ASM6):
        fail("asm6 is missing: put it at tools/asm6 (https://www.romhacking.net/utilities/674/)")
    r = subprocess.run([ASM6, "-q", "-l"] + rel, cwd=SRC, capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(binp):
        sys.stdout.write(r.stdout)
        sys.stderr.write(r.stderr)
        fail("asm6 failed")
    blob = open(binp, "rb").read()
    n = len(segs)
    lens = [blob[len(blob) - 2 * n + 2 * i] | blob[len(blob) - 2 * n + 2 * i + 1] << 8 for i in range(n)]
    out, pos = [], 0
    for (bank, start, end, name, lines), ln in zip(segs, lens):
        out.append((bank, start, end, name, blob[pos:pos + ln]))
        pos += ln
    if pos != len(blob) - 2 * n:
        fail("segment lengths do not add up")
    return out


def apply(rom, segs):
    used = []
    for bank, start, end, name, code in segs:
        win = 0xC000 if bank == FIXED else 0x8000
        if not (win <= start < win + BANK) or end > win + BANK:
            fail("segment %s: bank %02X lives at $%04X" % (name, bank, win))
        off = 16 + bank * BANK + (start - win)
        for (o2, e2, n2) in used:
            if off < e2 and o2 < off + len(code):
                fail("segment %s overlaps %s" % (name, n2))
        used.append((off, off + len(code), name))
        rom[off:off + len(code)] = code
        print("  %-26s %02X:%04X-%04X  %5d/%5d bytes" % (name, bank, start, start + len(code), len(code), end - start))


def write_symbols(path):
    """Labels from the asm6 listing, for the tests: NAME = $XXXX."""
    syms = {}
    lst = os.path.join(OUT, "build.lst")
    for line in open(lst, errors="replace"):
        m = re.match(r"^([0-9A-F]{5})\s+(?:[0-9A-F]{2} )*\s*([A-Za-z_][A-Za-z0-9_]*):", line)
        if m:
            syms[m.group(2)] = int(m.group(1), 16)
    with open(path, "w") as f:
        for k in sorted(syms):
            f.write("%s = $%04X\n" % (k, syms[k] & 0xFFFF))


# (target offset, source offset, length): where unchanged data in the new ROM
# came from in the original. The BPS writer copies these from the source.
COPIES = []


def base_copies():
    return [
        (16 + 8 * BANK + 0x3D00, 16 + 3 * BANK + 0x3C08, 0x300),       # the font copy
        (16, 16, (OLD_BANKS - 1) * BANK),                                # banks $00-$06
        (16 + FIXED * BANK, 16 + (OLD_BANKS - 1) * BANK, BANK),         # fixed bank
    ]


def src_offset(t):
    """Where the byte at target offset t came from in the original file."""
    for dst, src, n in COPIES:
        if dst <= t < dst + n:
            return t - dst + src
    return None


def write_bps(orig, new, path):
    """BPS patch: original ROM -> new ROM, copying moved data from the source."""
    def num(n):
        out = bytearray()
        while True:
            x = n & 0x7F
            n >>= 7
            if n == 0:
                out.append(0x80 | x)
                return out
            out.append(x)
            n -= 1

    body = bytearray(b"BPS1") + num(len(orig)) + num(len(new)) + num(0)
    src_rel = 0
    tgt_rel = 0
    t = 0
    lit = bytearray()

    def flush():
        nonlocal lit
        if lit:
            body.extend(num(((len(lit) - 1) << 2) | 1))
            body.extend(lit)
            lit = bytearray()

    while t < len(new):
        s = src_offset(t)
        n = 0
        if s is not None:
            while t + n < len(new) and src_offset(t + n) == s + n and new[t + n] == orig[s + n]:
                n += 1
        if n >= 4:
            flush()
            if s == t:
                body.extend(num(((n - 1) << 2) | 0))           # SourceRead
            else:
                body.extend(num(((n - 1) << 2) | 2))           # SourceCopy
                d = s - src_rel
                body.extend(num((abs(d) << 1) | (d < 0)))
                src_rel = s + n
            t += n
            continue
        r = 1
        while t + r < len(new) and new[t + r] == new[t] and r < 1 << 20:
            r += 1
        if r >= 8:
            lit.append(new[t])
            flush()
            body.extend(num(((r - 2) << 2) | 3))               # TargetCopy (RLE)
            d = t - tgt_rel
            body.extend(num((abs(d) << 1) | (d < 0)))
            tgt_rel = t + r - 1
            t += r
            continue
        lit.append(new[t])
        t += 1
    flush()
    body += zlib.crc32(orig).to_bytes(4, "little") + zlib.crc32(new).to_bytes(4, "little")
    body += zlib.crc32(body).to_bytes(4, "little")
    open(path, "wb").write(body)
    return len(body)


def apply_bps(orig, patch):
    """Reference BPS applier, used to check the patch we just wrote."""
    pos = 4

    def num():
        nonlocal pos
        data, shift = 0, 1
        while True:
            x = patch[pos]
            pos += 1
            data += (x & 0x7F) * shift
            if x & 0x80:
                return data
            shift <<= 7
            data += shift

    assert patch[:4] == b"BPS1"
    ssize, tsize, msize = num(), num(), num()
    pos += msize
    out = bytearray()
    src_rel = tgt_rel = 0
    while pos < len(patch) - 12:
        d = num()
        cmd, n = d & 3, (d >> 2) + 1
        if cmd == 0:
            out += orig[len(out):len(out) + n]
        elif cmd == 1:
            out += patch[pos:pos + n]
            pos += n
        else:
            o = num()
            o = -(o >> 1) if o & 1 else o >> 1
            if cmd == 2:
                src_rel += o
                out += orig[src_rel:src_rel + n]
                src_rel += n
            else:
                tgt_rel += o
                for _ in range(n):
                    out.append(out[tgt_rel])
                    tgt_rel += 1
    assert len(out) == tsize and zlib.crc32(out) == int.from_bytes(patch[-8:-4], "little")
    return bytes(out)


def main():
    os.makedirs(os.path.join(OUT, "gen"), exist_ok=True)
    data = load(ROM_IN, CV_MD5, "Castlevania (USA)")
    met = load(MET_IN, MET_MD5, "Metroid (USA)")
    import samus_gfx
    sprite_chr, n, cap = samus_gfx.build(met[16:], os.path.join(OUT, "gen"))
    rom = expand(data)
    # Castlevania's font (bank 3 $BC08), copied for the Game Over screen.
    font = 16 + 3 * BANK + 0x3C08
    open(os.path.join(OUT, "gen", "cv_font.bin"), "wb").write(data[font:font + 0x300])
    # Simon's sprite tiles are in bank 1 from $9008 on (tile 0); Samus's go
    # over the ones only Simon and his whip used.
    for tile, chunk in sprite_chr:
        off = 16 + 1 * BANK + (SIMON_CHR - 0x8000) + tile * 16
        rom[off:off + 32] = chunk
    print("samus: %d tile pairs of %d" % (n, cap))
    COPIES[:] = base_copies()
    prologue, segs = split_segments(os.path.join(SRC, "main.asm"))
    built = assemble(prologue, segs)
    print("segments:")
    apply(rom, built)
    write_symbols(os.path.join(OUT, "symbols.txt"))
    open(ROM_OUT, "wb").write(rom)
    print("built %s (%d KB)" % (os.path.relpath(ROM_OUT, REPO), len(rom) // 1024))
    n = write_bps(data, bytes(rom), BPS_OUT)
    if apply_bps(data, open(BPS_OUT, "rb").read()) != bytes(rom):
        fail("the BPS patch does not reproduce the ROM")
    print("      %s (%d bytes, for a ROM with CRC32 %08X)" % (os.path.relpath(BPS_OUT, REPO), n, zlib.crc32(data)))


if __name__ == "__main__":
    main()
