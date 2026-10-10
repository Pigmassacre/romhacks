"""Rebuild internal/build/patch.bin from a local SMB3 ROM, Gimmick! ROM, and out/smb3-gimmick.nes.

The patch stores only bytes that appear in neither ROM. Everything else is a copy
from the player's Super Mario Bros. 3 PRG or from the Gimmick! file.
"""
import os
import struct
import sys

ROOT = os.path.join(os.path.dirname(__file__), '..')
SMB = os.path.join(ROOT, 'Super Mario Bros III.nes')
GIM = os.path.join(ROOT, 'Gimmick! (Japan).nes')
HACK = os.path.join(ROOT, 'out', 'smb3-gimmick.nes')
OUT = os.path.join(ROOT, 'internal', 'build', 'patch.bin')

BANK = 0x2000
SMB_PRG = 0x40000
HACK_PRG = 0x80000
MIN = 8


def layout(smb):
    prg = bytearray(b'\xff' * HACK_PRG)
    src = smb[16:16 + SMB_PRG]
    for i in range(30):
        prg[i * BANK:(i + 1) * BANK] = src[i * BANK:(i + 1) * BANK]
    prg[62 * BANK:63 * BANK] = src[30 * BANK:31 * BANK]
    prg[63 * BANK:64 * BANK] = src[31 * BANK:32 * BANK]
    return prg


def index(data):
    idx = {}
    for i in range(len(data) - MIN + 1):
        idx.setdefault(data[i:i + MIN], []).append(i)
    return idx


def longest(hay, idx, needle, pos, src):
    if pos + MIN > len(needle):
        return 0, -1
    cands = idx.get(needle[pos:pos + MIN])
    if not cands:
        return 0, -1
    best = 0
    at = -1
    limit = len(needle) - pos
    for s in cands:
        n = MIN
        maxn = min(limit, len(hay) - s)
        while n < maxn and needle[pos + n] == hay[s + n]:
            n += 1
        if n > best:
            best = n
            at = s
    return best, at


def encode(base, hack_prg, smb_prg, gim):
    smb_idx = index(smb_prg)
    gim_idx = index(gim)
    ops = []
    pos = 0
    n = len(hack_prg)
    while pos < n:
        if base[pos] == hack_prg[pos]:
            pos += 1
            continue
        start = pos
        lits = bytearray()
        while pos < n and base[pos] != hack_prg[pos]:
            ls, ss = longest(smb_prg, smb_idx, hack_prg, pos, 'smb')
            lg, sg = longest(gim, gim_idx, hack_prg, pos, 'gim')
            if ls >= MIN or lg >= MIN:
                break
            lits.append(hack_prg[pos])
            pos += 1
        if lits:
            ops.append(('lit', start, bytes(lits)))
        if pos < n and base[pos] != hack_prg[pos]:
            ls, ss = longest(smb_prg, smb_idx, hack_prg, pos, 'smb')
            lg, sg = longest(gim, gim_idx, hack_prg, pos, 'gim')
            if ls >= lg:
                ops.append(('smb', pos, ss, ls))
                pos += ls
            else:
                ops.append(('gim', pos, sg, lg))
                pos += lg
    return ops


def apply(base, ops, smb_prg, gim):
    out = bytearray(base)
    for op in ops:
        if op[0] == 'lit':
            _, dest, data = op
            out[dest:dest + len(data)] = data
        elif op[0] == 'smb':
            _, dest, src, n = op
            out[dest:dest + n] = smb_prg[src:src + n]
        else:
            _, dest, src, n = op
            out[dest:dest + n] = gim[src:src + n]
    return out


def write(ops, path):
    buf = bytearray(b'S3GP')
    buf.append(1)
    buf += struct.pack('<I', len(ops))
    for op in ops:
        if op[0] == 'lit':
            _, dest, data = op
            buf.append(2)
            buf += struct.pack('<II', dest, len(data))
            buf += data
        elif op[0] == 'smb':
            _, dest, src, n = op
            buf.append(1)
            buf += struct.pack('<III', dest, src, n)
        else:
            _, dest, src, n = op
            buf.append(3)
            buf += struct.pack('<III', dest, src, n)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(buf)


def main():
    smb = open(SMB, 'rb').read()
    gim = open(GIM, 'rb').read()
    hack = open(HACK, 'rb').read()
    smb_prg = smb[16:16 + SMB_PRG]
    hack_prg = hack[16:16 + HACK_PRG]
    base = layout(smb)
    ops = encode(base, hack_prg, smb_prg, gim)
    got = apply(base, ops, smb_prg, gim)
    if got != hack_prg:
        sys.exit('patch does not reproduce the program')
    lits = sum(len(op[2]) for op in ops if op[0] == 'lit')
    copies = sum(1 for op in ops if op[0] != 'lit')
    print(f'{len(ops)} ops, {lits} literal bytes, {copies} copies')
    long = sorted((len(op[2]), op[1]) for op in ops if op[0] == 'lit')
    if long:
        print('longest literal', long[-1][0], 'at PRG', hex(long[-1][1]))
    write(ops, OUT)
    print('wrote', OUT, os.path.getsize(OUT), 'bytes')


if __name__ == '__main__':
    main()
