#!/usr/bin/env python3
"""Build Gimmick! 1.5 from your own copy of Gimmick! (Japan).

    python3 tools/build.py            # writes out/gimmick-1.5.nes and .bps

Steps:

1. Read `Gimmick! (Japan).nes` and check it is the right game (PRG and CHR
   checksum; the header is ignored, so both common dumps work).
2. Expand PRG from 256 KB to 512 KB and CHR from 128 KB to 256 KB. Original
   banks keep their numbers ($00-$1F); the fixed bank is copied to $3F,
   because the FME-7 always maps the last bank at $E000. PRG banks $20-$3E
   and CHR pages $80-$FF are new.
3. Assemble src/main.asm with asm6. The source is split into segments by
   `;@ seg <bank> <start> <end>` lines. Each segment is assembled at its CPU
   address and its bytes are written into that bank. A segment may be shorter
   than its range, never longer.
4. Rebuild the title screen to say "Gimmick! 1.5" (tools/title.py).
5. Write the ROM and BPS patches for both common dumps (iNES and NES 2.0
   headers). A patch copies everything it can from the original ROM, so it
   holds only the new code.
"""
import hashlib
import os
import zlib
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "src")
OUT = os.path.join(REPO, "out")
ROM_IN = os.path.join(REPO, "Gimmick! (Japan).nes")
ROM_OUT = os.path.join(OUT, "gimmick-1.5.nes")
BPS_OUT = os.path.join(OUT, "gimmick-1.5.bps")
BPS2_OUT = os.path.join(OUT, "gimmick-1.5-nes2.bps")
# The two common dumps of Gimmick! (Japan) differ only in their header.
HEADER_INES = bytes.fromhex("4e45531a101050400000000000000000")   # file CRC32 EEB6B362
HEADER_NES2 = bytes.fromhex("4e45531a101050480000000000000001")   # file CRC32 EE8879D5
ASM6 = os.path.join(REPO, "tools", "asm6")

# MD5 of the 256 KB PRG + 128 KB CHR of Gimmick! (J), without the header.
BODY_MD5 = "a46b4a632770b57f13d0327b346f4213"
BANK = 0x2000
OLD_PRG_BANKS = 32
NEW_PRG_BANKS = 64
CHR_SIZE = 128 * 1024
NEW_CHR_SIZE = 256 * 1024   # the FME-7's limit; pages $80-$FF are new
TITLE_PAGES = (0x80, 0x81, 0x82, 0x83)

SEG_RE = re.compile(r"^\s*;@\s*seg\s+\$?([0-9A-Fa-f]+)\s+\$?([0-9A-Fa-f]+)\s+\$?([0-9A-Fa-f]+)\s*(.*)$")


def fail(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


def load_rom():
    if not os.path.exists(ROM_IN):
        fail("put your copy of Gimmick! (Japan) at %r" % ROM_IN)
    data = open(ROM_IN, "rb").read()
    if data[:4] != b"NES\x1a":
        fail("%s is not an iNES file" % ROM_IN)
    body = data[16:]
    if len(body) != OLD_PRG_BANKS * BANK + CHR_SIZE:
        fail("unexpected ROM size %d" % len(data))
    md5 = hashlib.md5(body).hexdigest()
    if md5 != BODY_MD5:
        fail("this is not Gimmick! (Japan): body md5 %s" % md5)
    return data


def expand(data):
    prg = data[16:16 + OLD_PRG_BANKS * BANK]
    chr_ = data[16 + OLD_PRG_BANKS * BANK:]
    banks = [prg[i * BANK:(i + 1) * BANK] for i in range(OLD_PRG_BANKS)]
    new = banks + [b"\xff" * BANK] * (NEW_PRG_BANKS - OLD_PRG_BANKS)
    new[NEW_PRG_BANKS - 1] = banks[OLD_PRG_BANKS - 1]
    chr_ = chr_ + b"\x00" * (NEW_CHR_SIZE - CHR_SIZE)
    header = bytearray(data[:16])
    header[4] = NEW_PRG_BANKS * BANK // 0x4000
    header[5] = NEW_CHR_SIZE // 0x2000
    header[6] = 0x50 | (header[6] & 0x0F)  # mapper 69: low nibble 5
    header[7] = 0x40                         # mapper 69: high nibble 4, plain iNES
    header[8:16] = bytes(8)
    return bytearray(bytes(header) + b"".join(new) + chr_)


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


def find_asm6():
    """tools/asm6, built from the disassembly's copy of asm6.c if needed."""
    if os.path.exists(ASM6):
        return ASM6
    src = os.path.join(REPO, "ref", "gimmick", "asm6.c")
    if os.path.exists(src):
        r = subprocess.run(["cc", "-O2", "-w", "-o", ASM6, src], capture_output=True, text=True)
        if r.returncode == 0:
            return ASM6
        sys.stderr.write(r.stderr)
    fail("asm6 is missing: put it at tools/asm6 (https://www.romhacking.net/utilities/674/)")


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
    r = subprocess.run([find_asm6(), "-q", "-l"] + rel, cwd=SRC, capture_output=True, text=True)
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


def bank_window(bank):
    """CPU window a bank is meant to be used in, for sanity checks."""
    return 0xE000 if bank == NEW_PRG_BANKS - 1 else None


def apply(rom, segs):
    used = []
    for bank, start, end, name, code in segs:
        win = bank_window(bank)
        if win is not None and not (win <= start < win + BANK):
            fail("segment %s: bank %02X lives at $%04X" % (name, bank, win))
        if (start & 0x1FFF) + (end - start) > BANK:
            fail("segment %s crosses a bank boundary" % name)
        off = 16 + bank * BANK + (start & 0x1FFF)
        for (o2, e2, n2) in used:
            if off < e2 and o2 < off + len(code):
                fail("segment %s overlaps %s" % (name, n2))
        used.append((off, off + len(code), name))
        rom[off:off + len(code)] = code
        print("  %-22s %02X:%04X-%04X  %4d/%4d bytes" % (name, bank, start, start + len(code), len(code), end - start))


# (target offset, source offset, length): where unchanged data in the new ROM
# came from in the original. The BPS writer copies these from the source.
COPIES = []


def base_copies():
    prg = OLD_PRG_BANKS * BANK
    return [
        (16, 16, prg),                                                   # PRG banks $00-$1F
        (16 + (NEW_PRG_BANKS - 1) * BANK, 16 + (OLD_PRG_BANKS - 1) * BANK, BANK),   # fixed bank
        (16 + NEW_PRG_BANKS * BANK, 16 + prg, CHR_SIZE),                 # CHR
    ]


def src_offset(t):
    """Where the byte at target offset t came from in the original file."""
    for dst, src, n in COPIES:
        if dst <= t < dst + n:
            return t - dst + src
    return None


def write_bps(orig, new, path):
    """BPS patch: original ROM -> new ROM, copying moved data from the source."""
    import zlib

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
    import zlib
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
    os.makedirs(OUT, exist_ok=True)
    data = load_rom()
    rom = expand(data)
    COPIES[:] = base_copies()
    prologue, segs = split_segments(os.path.join(SRC, "main.asm"))
    built = assemble(prologue, segs)
    print("segments:")
    apply(rom, built)
    import title
    chr_base = 16 + NEW_PRG_BANKS * BANK
    copied = []
    n = title.patch(rom, chr_base, TITLE_PAGES, copied)
    for dst, page in copied:
        COPIES.append((dst, 16 + OLD_PRG_BANKS * BANK + page * 1024, 1024))
    print("  title: \"1.5\" in %d new tiles, CHR pages %s" % (n, " ".join("%02X" % p for p in TITLE_PAGES)))
    open(ROM_OUT, "wb").write(rom)
    print("built %s (%d KB)" % (os.path.relpath(ROM_OUT, REPO), len(rom) // 1024))
    title.preview(rom, chr_base, os.path.join(OUT, "title.png"))
    for header, path in ((HEADER_INES, BPS_OUT), (HEADER_NES2, BPS2_OUT)):
        src = header + data[16:]
        n = write_bps(src, bytes(rom), path)
        if apply_bps(src, open(path, "rb").read()) != bytes(rom):
            fail("the BPS patch does not reproduce the ROM")
        print("      %s (%d bytes, for a dump with CRC32 %08X)" % (os.path.relpath(path, REPO), n, zlib.crc32(src)))


if __name__ == "__main__":
    main()
